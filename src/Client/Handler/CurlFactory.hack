namespace HackHttp\Client\Handler;

use HackHttp\Client\Exception\ConnectException;
use HackHttp\Client\Exception\RequestException;

use namespace HackPromises as P;
use namespace HackHttp\Message as HM;

use HackPromises\FulfilledPromise;
use HackPromises\PromiseInterface;

use HackHttp\Client\RequestOptions;
use HackHttp\Client\TransferStats;
use HackHttp\Client\Utils;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\LazyOpenStream;

use type HackHttp\Client\RequestHandlerCallable;

use namespace HH;
use namespace HH\Lib\C;
use namespace HH\Lib\Dict;
use type HH\Lib\File\WriteMode;
use type HH\Vector;
use HH\Lib\Str;
use type HH\Map;


/**
 * Creates curl resources from a request
 *
 * @final
 */
final class CurlFactory implements CurlFactoryInterface
{
    const CURL_VERSION_STR = 'curl_version';


    public function __construct()
    {
    }

    /**
     * @param RequestInterface $request request
     * @param dict<arraykey, mixed> $options request options
     */
    public function create(RequestInterface $request, dict<arraykey, mixed> $options): EasyHandle
    {
        $options_curl = HH\idx($options, 'curl');
        
        if($options_curl is dict<_,_>) {
            $options_curl_map = new Map($options_curl);

            $body_as_string = HH\idx($options_curl_map, 'body_as_string');
            if($body_as_string is nonnull) {
                $options['_body_as_string'] = $body_as_string;
                $options_curl_map->removeKey('body_as_string');
                $options['curl'] = $options_curl_map->toDArray() ;
            }
        }

        $easy = new EasyHandle($request, $options);
        $conf = new Map($this->getDefaultConf($easy));
        $this->applyMethod($easy, $conf);
        $this->applyHandlerOptions($easy, $conf);
        $this->applyHeaders($easy, $conf);
        $conf->removeKey('_headers');

        // Add handler options from the request configuration options
        $options_curl = HH\idx($options, 'curl');
        if ($options_curl is dict<_,_>) {
            $conf = new Map(Dict\merge($conf->toDArray(), $options_curl));
        }

        $conf[\CURLOPT_HEADERFUNCTION] = $this->createHeaderFn($easy);
        $handle = \curl_init();
        \curl_setopt_array($handle, $conf->toDArray());
        $easy->setHandle($handle);

        return $easy;
    }

    public function release(EasyHandle $easy): void
    {
        $handle = $easy->getHandle();
        $easy->setHandle(null);

        if ($handle is resource) {
            \curl_close($handle);
        }
    }

    /**
     * Completes a cURL transaction, either returning a response promise or a
     * rejected promise.
     *
     * @param RequestHandlerCallable $handler
     * @param CurlFactoryInterface  $factory Dictates how the handle is released
     *
     * @return PromiseInterface
     */
    public static function finish(RequestHandlerCallable $handler, 
        EasyHandle $easy, CurlFactoryInterface $factory): PromiseInterface
    {
        if ($easy->getOption(RequestOptions::ON_STATS)) {
            self::invokeStats($easy);
        } 

        $response = $easy->getResponse();
        if ($response is null || $easy->getErrno()) {
            return self::finishError($handler, $easy, $factory);
        }

        // Return the response if it is present and there is no error.
        $factory->release($easy);

        // Rewind the body of the response if possible.
        $body = $response->getBody();
        if ($body->isSeekable()) {
            $body->rewind();
        }

        return new FulfilledPromise($response);
    }

    private static function invokeStats(EasyHandle $easy): void
    {
        $ch = $easy->getHandle();
        if($ch is resource) {
            $curlStats = \curl_getinfo($ch);
            $curlStats['appconnect_time'] = \curl_getinfo($ch, \CURLINFO_APPCONNECT_TIME);
            $stats = new TransferStats($easy->getRequest(),
                        $easy->getResponse(),
                        HH\idx($curlStats, 'total_time'),
                        $easy->getErrno(),
                        $curlStats);
            $on_stats = $easy->getOption(RequestOptions::ON_STATS);
            if($on_stats is TransferStatsCallbackInterface) {
                $on_stats->callback($stats);
            }
        }
    }

    private static function finishError(RequestHandlerCallable $handler, 
        EasyHandle $easy, CurlFactoryInterface $factory): PromiseInterface
    {
        // Get error information and release the handle to the factory.
        $ch = $easy->getHandle();

        if($ch is resource) {
            $ctx = Dict\merge(dict<arraykey, mixed>[
                    'errno' => $easy->getErrno(),
                    'error' => \curl_error($ch),
                    'appconnect_time' => \curl_getinfo($ch, \CURLINFO_APPCONNECT_TIME)], 
                    \curl_getinfo($ch));
            $ctx[self::CURL_VERSION_STR] = \curl_version()['version'];
            $factory->release($easy);

            // Retry when nothing is present or when curl failed to rewind.
            if ($easy->getOption('_err_message') is null && ( $easy->getErrno() === 65)) {
                return self::retryFailedRewind($handler, $easy, $ctx);
            }

            return self::createRejection($easy, $ctx);
        }

        throw new \RuntimeException("Curl handle is not a resource");
    }

    private static function createRejection(EasyHandle $easy, dict<arraykey, mixed> $ctx): PromiseInterface
    {
        $connectionErrors = dict<int, bool>[
            \CURLE_OPERATION_TIMEOUTED  => true,
            \CURLE_COULDNT_RESOLVE_HOST => true,
            \CURLE_COULDNT_CONNECT      => true,
            \CURLE_SSL_CONNECT_ERROR    => true,
            \CURLE_GOT_NOTHING          => true,
        ];

        if ($easy->getCreateResponseException()) {
            return P\Create::rejectionFor(
                new RequestException(
                    'An error was encountered while creating the response',
                    $easy->getRequest(),
                    $easy->getResponse(),
                    $easy->getCreateResponseException(),
                    $ctx
                )
            );
        }

        // If an exception was encountered during the onHeaders event, then
        // return a rejected promise that wraps that exception.
        if ($easy->getOnHeadersException()) {
            return P\Create::rejectionFor(
                new RequestException(
                    'An error was encountered during the on_headers event',
                    $easy->getRequest(),
                    $easy->getResponse(),
                    $easy->getOnHeadersException(),
                    $ctx
                )
            );
        }

        $ctx_errno =  HH\idx($ctx, 'errno');

        if($ctx_errno is arraykey) {
            $message = \sprintf(
                'cURL error %s: %s (%s)',
                $ctx_errno,
                $ctx_errno,
                'see https://curl.haxx.se/libcurl/c/libcurl-errors.html'
            );
            $ctx_error =  HH\idx($ctx, 'error');

            if($ctx_error is string) {
                $uriString = $easy->getRequest()->getUri()->__toString();
                if ($uriString !== '' && Str\search($ctx_error, $uriString) is null) {
                    $message .= \sprintf(' for %s', $uriString);
                }

                // Create a connection exception if it was a specific error code.
                $error = isset($connectionErrors[$easy->getErrno()])
                    ? new ConnectException($message, $easy->getRequest(), null, $ctx)
                    : new RequestException($message, $easy->getRequest(), $easy->getResponse(), null, $ctx);

                return P\Create::rejectionFor($error);
            } else {
                throw new \RuntimeException("ctx['error'] is not a string");
            }
        } else {
            throw new \RuntimeException("ctx['errno'] is not an arraykey");
        }

       
    }

    /**
     * @return dict<arraykey, mixed>
     */
    private function getDefaultConf(EasyHandle $easy): dict<arraykey, mixed>
    {
        $conf = dict[
            '_headers'              => $easy->getRequest()->getHeaders(),
            \CURLOPT_CUSTOMREQUEST  => $easy->getRequest()->getMethod(),
            \CURLOPT_URL            => $easy->getRequest()->getUri()->withFragment('')->__toString(),
            \CURLOPT_RETURNTRANSFER => false,
            \CURLOPT_HEADER         => false,
            \CURLOPT_CONNECTTIMEOUT => 150,
        ];

        if (\defined('CURLOPT_PROTOCOLS')) {
            $conf[\CURLOPT_PROTOCOLS] = \CURLPROTO_HTTP | \CURLPROTO_HTTPS;
        }

        $version = $easy->getRequest()->getProtocolVersion();
        if ($version === '1.1') {
            $conf[\CURLOPT_HTTP_VERSION] = \CURL_HTTP_VERSION_1_1;
        } elseif ($version === '2.0') {
            $conf[\CURLOPT_HTTP_VERSION] = \CURL_HTTP_VERSION_2_0;
        } else {
            $conf[\CURLOPT_HTTP_VERSION] = \CURL_HTTP_VERSION_1_0;
        }

        return $conf;
    }

    private function applyMethod(EasyHandle $easy, Map<arraykey, mixed> $conf): void
    {
        $body = $easy->getRequest()->getBody();
        $size = $body->getSize();

        if ($size === null || $size > 0) {
            $this->applyBody($easy->getRequest(), $easy->getOptions(), $conf);
            return;
        }

        $method = $easy->getRequest()->getMethod();
        if ($method === 'PUT' || $method === 'POST') {
            // See https://tools.ietf.org/html/rfc7230#section-3.3.2
            if (!$easy->getRequest()->hasHeader('Content-Length')) {
                $httpheader = HH\idx($conf, \CURLOPT_HTTPHEADER);
                if($httpheader is vec<_>) {
                    $httpheader[] = 'Content-Length: 0';
                    $conf[\CURLOPT_HTTPHEADER] = $httpheader;
                } else {
                    $conf[\CURLOPT_HTTPHEADER] = vec['Content-Length: 0'];
                }
            }
        } elseif ($method === 'HEAD') {
            $conf[\CURLOPT_NOBODY] = true;
            $conf->removeKey(\CURLOPT_WRITEFUNCTION);
            $conf->removeKey(\CURLOPT_READFUNCTION);
            $conf->removeKey(\CURLOPT_FILE);
            $conf->removeKey(\CURLOPT_INFILE);
        }
    }

    private function applyBody(RequestInterface $request, dict<arraykey, mixed> $options, Map<arraykey, mixed> $conf): void
    {
        $size = $request->hasHeader('Content-Length')
            ? (int) $request->getHeaderLine('Content-Length')
            : null;

        // Send the body as a string if the size is less than 1MB OR if the
        // [curl][body_as_string] request value is set.
        if (($size !== null && $size < 1000000) || HH\idx($options,'_body_as_string') is nonnull) {
            $conf[\CURLOPT_POSTFIELDS] = $request->getBody()->__toString();
            // Don't duplicate the Content-Length header
            $this->removeHeader('Content-Length', $conf);
            $this->removeHeader('Transfer-Encoding', $conf);
        } else {
            $conf[\CURLOPT_UPLOAD] = true;
            if ($size !== null) {
                $conf[\CURLOPT_INFILESIZE] = $size;
                $this->removeHeader('Content-Length', $conf);
            }
            $body = $request->getBody();
            if ($body->isSeekable()) {
                $body->rewind();
            }
            $conf[\CURLOPT_READFUNCTION] = (mixed $ch, mixed $fd, ?int $length): string ==> {
                return $body->read($length);
            };
        }
    }

    private function applyHeaders(EasyHandle $easy, Map<arraykey, mixed> $conf): void
    {
        $curlopt_httpheader = HH\idx($conf, \CURLOPT_HTTPHEADER);

        if($curlopt_httpheader is null) {
            $curlopt_httpheader = vec[];
        }

        if($curlopt_httpheader is vec<_>) {
            $headers = HH\idx($conf, '_headers');
            if($headers is dict<_,_>) {
                foreach ($headers as $name => $values) {
                    if($values is vec<_>) {
                        $values = HM\Utils::filterTraversable<string>($values);

                        foreach ($values as $value) {
                            $value = (string) $value;
                            if ($value === '') {
                                // cURL requires a special format for empty headers.
                                $curlopt_httpheader[] = "$name;";
                            } else {
                                $curlopt_httpheader[] = "$name: $value";
                            }
                        }
                    }
                } 
            }

            // Remove the Accept header if one was not set
            if (!$easy->getRequest()->hasHeader('Accept')) {
                $curlopt_httpheader[] = 'Accept:';
            }

            if(C\count($curlopt_httpheader) > 0) {
                $conf[\CURLOPT_HTTPHEADER] = $curlopt_httpheader;
            }
        }
    }

    /**
     * Remove a header from the options array.
     *
     * @param string $name    Case-insensitive header to remove
     * @param Map<arraykey, mixed>  $options Array of options to modify
     */
    private function removeHeader(string $name, Map<arraykey, mixed> $options): void
    {
        $headers = HH\idx($options, '_headers');
        if($headers is dict<_,_>) {
            $headers = new Map($headers);

            $keys = $headers->keys();
            $keys = HM\Utils::filterTraversable<string>($keys);
            foreach ($keys as $key) {
                if (!\strcasecmp($key, $name)) {
                    $headers->removeKey($key);
                    $options['_headers'] = $headers->toDArray();
                    return;
                }
            }
        }
    }

    private function applyHandlerOptions(EasyHandle $easy, Map<arraykey, mixed> $conf): void
    {
        $options_verify = $easy->getOption(RequestOptions::VERIFY);

        if ($options_verify is nonnull) {
            if ($options_verify === false) {
                $conf->removeKey(\CURLOPT_CAINFO);
                $conf[\CURLOPT_SSL_VERIFYHOST] = 0;
                $conf[\CURLOPT_SSL_VERIFYPEER] = false;
            } else {
                $conf[\CURLOPT_SSL_VERIFYHOST] = 2;
                $conf[\CURLOPT_SSL_VERIFYPEER] = true;
                
                if ($options_verify is string && $options_verify) {
                    
                    // Throw an error if the file/folder/link path is not valid or doesn't exist.
                    if (!\file_exists($options_verify)) {
                        throw new \InvalidArgumentException("SSL CA bundle not found: {$options_verify}");
                    }
                    // If it's a directory or a link to a directory use CURLOPT_CAPATH.
                    // If not, it's probably a file, or a link to a file, so use CURLOPT_CAINFO.
                    if (\is_dir($options_verify)) {
                        $conf[\CURLOPT_CAPATH] = $options_verify;
                    } elseif ( \is_link($options_verify) === true) {
                        $verifyLink = \readlink($options_verify);
                        if($verifyLink !== false && \is_dir($verifyLink)) {
                            $conf[\CURLOPT_CAPATH] = $options_verify;
                        } else {
                            $conf[\CURLOPT_CAINFO] = $options_verify;
                        }
                    } else {
                        $conf[\CURLOPT_CAINFO] = $options_verify;
                    }
                }
            }
        }

        $options_curl = $easy->getOption('curl');
        if ( (!($options_curl is dict<_,_>) || !isset($options_curl[\CURLOPT_ENCODING]))
             && $easy->getOption(RequestOptions::DECODE_CONTENT)) {
            $accept = $easy->getRequest()->getHeaderLine('Accept-Encoding');
            if ($accept) {
                $conf[\CURLOPT_ENCODING] = $accept;
            } else {
                // The empty string enables all available decoders and implicitly
                // sets a matching 'Accept-Encoding' header.
                $conf[\CURLOPT_ENCODING] = '';
                // But as the user did not specify any acceptable encodings we need
                // to overwrite this implicit header with an empty one.
                $http_header = HH\idx($conf, \CURLOPT_HTTPHEADER);
                if($http_header is vec<_>) {
                    $http_header[] = 'Accept-Encoding:';
                    $conf[\CURLOPT_HTTPHEADER] = $http_header;
                } else {
                    $conf[\CURLOPT_HTTPHEADER] = vec['Accept-Encoding:'];
                }
            }
        }

        $options_sink = $easy->getOption(RequestOptions::SINK);
        $sink = null;

        if ($options_sink is null || !($options_sink is string)) {
            $sink = HM\Utils::streamFor($options_sink);
        } elseif (!\is_dir(\dirname($options_sink))) {
            // Ensure that the directory exists before failing in curl.
            throw new \RuntimeException(\sprintf('Directory %s does not exist for sink value of %s', \dirname($options_sink), $options_sink));
        } else {
            $sink = new LazyOpenStream($options_sink, WriteMode::APPEND);
        }
        $easy->setSink($sink);
        $conf[\CURLOPT_WRITEFUNCTION] = (mixed $ch, string $write): int ==> {
            return $sink->write($write);
        };

        $timeoutRequiresNoSignal = false;
        $options_timeout = $easy->getOption(RequestOptions::TIMEOUT);
        if ($options_timeout is num) {
            $timeoutRequiresNoSignal = $timeoutRequiresNoSignal || ($options_timeout < 1);
            $conf[\CURLOPT_TIMEOUT_MS] = $options_timeout * 1000;
        }

        // CURL default value is CURL_IPRESOLVE_WHATEVER
        $options_force_ip_resolve = $easy->getOption(RequestOptions::FORCE_IP_RESOLVE);
        if ($options_force_ip_resolve is string) {
            if ('v4' === $options_force_ip_resolve) {
                $conf[\CURLOPT_IPRESOLVE] = \CURL_IPRESOLVE_V4;
            } elseif ('v6' === $options_force_ip_resolve) {
                $conf[\CURLOPT_IPRESOLVE] = \CURL_IPRESOLVE_V6;
            }
        }

        $options_connect_timeout = $easy->getOption(RequestOptions::CONNECT_TIMEOUT);
        if ($options_connect_timeout is num) {
            $timeoutRequiresNoSignal = $timeoutRequiresNoSignal || ($options_connect_timeout < 1);
            $conf[\CURLOPT_CONNECTTIMEOUT_MS] = $options_connect_timeout * 1000;
        }

        if ($timeoutRequiresNoSignal && \strtoupper(Str\slice(\PHP_OS, 0, 3)) !== 'WIN') {
            $conf[\CURLOPT_NOSIGNAL] = true;
        }

        $options_proxy = $easy->getOption(RequestOptions::PROXY);
        if ($options_proxy is nonnull) {
            if (!($options_proxy is dict<_,_>)) {
                $conf[\CURLOPT_PROXY] = $options_proxy;
            } else {
                $scheme = $easy->getRequest()->getUri()->getScheme();
                if (isset($options_proxy[$scheme])) {
                    $host = $easy->getRequest()->getUri()->getHost();
                    $options_proxy_no = HH\idx($options_proxy, 'no');

                    if($options_proxy_no is vec<_>) {
                        $options_proxy_no = HM\Utils::filterTraversable<string>($options_proxy_no);
                        if(!Utils::isHostInNoProxy($host, $options_proxy_no)) {
                            $conf[\CURLOPT_PROXY] = $options_proxy[$scheme];
                        }
                    } else {
                        $conf[\CURLOPT_PROXY] = $options_proxy[$scheme];
                    }
                }
            }
        }

        $cert = $easy->getOption(RequestOptions::CERT);

        if ($cert is nonnull) {
            if ($cert is vec<_>) {
                $conf[\CURLOPT_SSLCERTPASSWD] = $cert[1];
                $cert = $cert[0];
            }
            if ($cert is string) {
                if(!\file_exists($cert)) {
                    throw new \InvalidArgumentException("SSL certificate file not found: {$cert}");
                }
            } else {
                throw new \InvalidArgumentException("SSL certificate is not of type string");
            }
           
            $ext = \pathinfo($cert, \PATHINFO_EXTENSION);
            if (\preg_match('#^(der|p12)$#i', $ext)) {
                $conf[\CURLOPT_SSLCERTTYPE] = \strtoupper($ext);
            }
            $conf[\CURLOPT_SSLCERT] = $cert;
        }

        $options_ssl_key = $easy->getOption(RequestOptions::SSL_KEY);
        $sslKey = null;
        if ($options_ssl_key is nonnull) {
            if (HH\is_any_array($options_ssl_key)) {
                $ssl_key_values = \array_values($options_ssl_key);
                $sslKey = $ssl_key_values[0];
                if (\count($options_ssl_key) === 2) {
                    $conf[\CURLOPT_SSLKEYPASSWD] = $ssl_key_values[1];
                } 
            }

            $sslKey = $sslKey ?? $options_ssl_key;

            if($sslKey is string) {
                if (!\file_exists($sslKey)) {
                    throw new \InvalidArgumentException("SSL private key file not found: {$sslKey}");
                }
            } else {
                throw new \InvalidArgumentException("SSL private key is not of type string");
            }
            $conf[\CURLOPT_SSLKEY] = $sslKey;
        }

        $progress = $easy->getOption(RequestOptions::PROGRESS);
        if ($progress is nonnull) {
            if($progress is ProgressCallbackInterface) {
                $conf[\CURLOPT_NOPROGRESS] = false;
                $conf[\CURLOPT_PROGRESSFUNCTION] =  (mixed...$args) ==> {
                        $progress->callback($args);
                };
            } else {
                throw new \InvalidArgumentException('progress client option must be a ProgressCallbackInterface');
            }
        }
        
        $options_debug = $easy->getOption('debug');
        if ($options_debug is resource) {
            $conf[\CURLOPT_STDERR] = $options_debug;
            $conf[\CURLOPT_VERBOSE] = true;
        } else if($options_debug) {
            $conf[\CURLOPT_STDERR] = \defined('STDOUT') ? \STDOUT:  HM\Utils::streamFor(null);
            $conf[\CURLOPT_VERBOSE] = true;
        }

        $options_on_stat = $easy->getOption(RequestOptions::ON_STATS);
        if($options_on_stat is nonnull && !($options_on_stat is TransferStatsCallbackInterface)) {
            throw new \InvalidArgumentException('on_stats client option must be a TransferStatsCallbackInterface');
        }
    }

    /**
     * This function ensures that a response was set on a transaction. If one
     * was not set, then the request is retried if possible. This error
     * typically means you are sending a payload, curl encountered a
     * "Connection died, retrying a fresh connect" error, tried to rewind the
     * stream, and then encountered a "necessary data rewind wasn't possible"
     * error, causing the request to be sent through curl_multi_info_read()
     * without an error status.
     *
     * @param RequestHandlerCallable $handler: PromiseInterface $handler
     */
    private static function retryFailedRewind(RequestHandlerCallable $handler, 
        EasyHandle $easy, dict<arraykey, mixed> $ctx): PromiseInterface
    {
        try {
            // Only rewind if the body has been read from.
            $body = $easy->getRequest()->getBody();
            if ($body->tell() > 0) {
                $body->rewind();
            }
        } catch (\RuntimeException $e) {
            $ctx['error'] = 'The connection unexpectedly failed without '
                . 'providing an error. The request would have been retried, '
                . 'but attempting to rewind the request body failed. '
                . 'Exception: ' . $e->__toString();
            return self::createRejection($easy, $ctx);
        }

        // Retry no more than 3 times before giving up.
        $_curl_retries = $easy->getOption('_curl_retries');

        if ($_curl_retries is null) {
            $easy->setOption('_curl_retries', 1);
        } elseif ($_curl_retries === 2) {
            $ctx['error'] = 'The cURL request was retried 3 times '
                . 'and did not succeed. The most likely reason for the failure '
                . 'is that cURL was unable to rewind the body of the request '
                . 'and subsequent retries resulted in the same error. Turn on '
                . 'the debug option to see what went wrong. See '
                . 'https://bugs.php.net/bug.php?id=47204 for more information.';
            return self::createRejection($easy, $ctx);
        } elseif ($_curl_retries is int){
            $_curl_retries += 1;
            $easy->setOption('_curl_retries', $_curl_retries);
        }

        return $handler($easy->getRequest(), $easy->getOptions());
    }

    private function createHeaderFn(EasyHandle $easy): HeaderCallback
    {
        $onHeaders = $easy->getOption(RequestOptions::ON_HEADERS);

        if ($onHeaders is nonnull) {
            if (!($onHeaders is HeaderCallbackInterface)) {
                throw new \InvalidArgumentException('on_headers must be a HeaderCallbackInterface');
            }
        } else {
            $onHeaders = null;
        }

        return  (resource $ch, string $h): int ==> {
            $value = \trim($h);
            if ($value === '') {
                try {
                    $easy->createResponse();
                } catch (\Exception $e) {
                    $easy->setCreateResponseException($e);
                    return -1;
                }
                if ($onHeaders !== null) {
                    try {
                        $onHeaders->callback($easy->getResponse());
                    } catch (\Exception $e) {
                        // Associate the exception with the handle and trigger
                        // a curl header write error by returning 0.
                        $easy->setOnHeadersException($e);
                        return -1;
                    }
                }
            } else {
                $easy->addHeader($value);
            }
            return \strlen($h);
        };
    }
}

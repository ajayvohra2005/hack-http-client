namespace HackHttp\Client;

use namespace HH;
use namespace HH\Lib\C;
use namespace HH\Lib\Dict;
use namespace HH\Lib\Str;
use type HH\Map;

use namespace HackHttp\Message as HM;
use namespace HackPromises as P;

use type HackHttp\Client\Cookie\CookieJar;
use type HackHttp\Client\Exception\ClientException;
use type HackHttp\Client\Exception\InvalidArgumentException;
use type HackHttp\Client\Exception\RequestException;
use type HackPromises\PromiseInterface;
use type HackHttp\Message\RequestInterface;
use type HackHttp\Message\ResponseInterface;
use type HackHttp\Message\UriInterface;
use type HackHttp\Message\Request;
use type HackHttp\Message\UriResolver;
use type HackHttp\Message\MultipartStream;

/**
 * @final
 */
class Client implements ClientInterface
{
    use ClientTrait;

    /**
     * @var dict<arraykey, mixed> Default request options
     */
    private dict<arraykey,  mixed> $config;

    /**
     * Clients accept an dict<arraykey, mixed> of constructor parameters.
     *
     * Here's an example of creating a client using a base_uri and an dict<arraykey, mixed> of
     * default request options to apply to each request:
     *
     *     $client = new Client([
     *         'base_uri'        => 'http://www.foo.com/1.0/',
     *         RequestOptions::TIMEOUT         => 0,
     *         'allow_redirects' => false,
     *         RequestOptions::PROXY           => '192.168.16.1:10'
     *     ]);
     *
     * Client configuration settings include the following options:
     *
     * - handler: (RequestHandler) Interface that transfers HTTP requests over the
     *   wire. The function is called with a HackHttp\Message\RequestInterface
     *   and dict<arraykey, mixed> of transfer options, and must return a
     *   HackPromises\PromiseInterface that is fulfilled with a
     *   HackHttp\Message\ResponseInterface on success.
     *   If no handler is provided, a default handler will be created
     *   that enables all of the request options below by attaching all of the
     *   default middleware to the handler.
     * - base_uri: (mixed) Base URI of the client that is merged
     *   into relative URIs. Can be a string or instance of UriInterface.
     * - **: any request option
     *
     * @param dict<arraykey, mixed> $config Client configuration settings.
     *
     * @see HackHttp\Client\RequestOptions for a list of available request options.
     */
    public function __construct(dict<arraykey, mixed> $config = dict[])
    {
        $handler = HH\idx($config,'handler');

        if ($handler is null) {
            $config['handler'] = HandlerStack::create();
        } elseif ($handler is RequestHandlerInterface) {
            $config['handler'] = $handler;
        } else {
            throw new \InvalidArgumentException('Request handler is not RequestHandlerInterface');
        }

        // Convert the base_uri to a UriInterface
        $base_uri = HH\idx($config, 'base_uri');
        if ($base_uri is nonnull) {
            $config['base_uri'] = HM\Utils::uriFor($base_uri);
        }

        $this->configureDefaults($config);
    }

    /**
     * @return dict<arraykey,  mixed> client configuration 
     */
    public function getConfig(): dict<arraykey,  mixed>
    {
        return $this->config;
    }

    /**
     * Asynchronously send an HTTP request.
     *
     * @param dict<arraykey,  mixed> $options Request options to apply to the given
     *                       request and to the transfer. See HackHttp\Client\RequestOptions.
     *
     * @return PromiseInterface
     */
    public function sendAsync(RequestInterface $request, dict<arraykey,  mixed> $options = dict[]): PromiseInterface
    {
        // Merge the base URI into the request URI if needed.
        $options = $this->prepareDefaults($options);

        return $this->transfer(
            $request->withUri($this->buildUri($request->getUri(), $options), $request->hasHeader('Host')),
            $options
        );
    }

    /**
     * Send an HTTP request.
     *
     * @param dict<arraykey,  mixed> $options Request options to apply to the given
     *                       request and to the transfer. See HackHttp\Client\RequestOptions.
     *
     * @return ResponseInterface
     * @throws ClientException
     */
    public function send(RequestInterface $request, dict<arraykey,  mixed> $options = dict[]): ResponseInterface
    {
        $options[RequestOptions::SYNCHRONOUS] = true;
        $promise =  $this->sendAsync($request, $options);
        $retval = $promise->wait();
        if($retval is ResponseInterface) {
            return $retval;
        }

        throw new \RuntimeException("Response value is not a ResponseInterface");
    }

    /**
     * The HttpClient specifies this method.
     *
     * @inheritDoc
     */
    public function sendRequest(RequestInterface $request): ResponseInterface
    {
        $options = dict[];
        $options[RequestOptions::SYNCHRONOUS] = true;
        $options[RequestOptions::ALLOW_REDIRECTS] = false;
        $options[RequestOptions::HTTP_ERRORS] = false;

        $retval =  $this->sendAsync($request, $options)->wait();
        if($retval is ResponseInterface) {
            return $retval;
        }

        throw new \RuntimeException("Response value is not a ResponseInterface");
    }

    /**
     * Create and send an asynchronous HTTP request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an dict<arraykey, mixed> to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param string  $method  HTTP method
     * @param mixed $uri     URIInterface, or string.
     * @param dict<arraykey, mixed>  $options Request options to apply. See HackHttp\Client\RequestOptions.
     */
    public function requestAsync(string $method, mixed $uri = '', dict<arraykey,  mixed> $options = dict[]): PromiseInterface
    {
        $options = $this->prepareDefaults($options);
        // Remove request modifying parameter because it can be done up-front.
        $headers = HH\idx($options,RequestOptions::HEADERS) ?? dict[];
        $body = HH\idx($options, RequestOptions::BODY) ?? null;
        $version = HH\idx($options, RequestOptions::VERSION) ?? '1.1';
        // Merge the URI into the base URI.
        $uri = $this->buildUri(HM\Utils::uriFor($uri), $options);
        if (HH\is_any_array($body)) {
            throw $this->invalidBody();
        }

        if($headers is dict<_,_> && $version is string) {
            $headers = HM\Utils::filterHeaders($headers);
            $request = new Request($method, $uri, $headers, $body, $version);
            
            $options_map = new Map($options);

            $options_map->removeKey(RequestOptions::HEADERS)->removeKey(RequestOptions::BODY)->removeKey(RequestOptions::VERSION);
            $options = $options_map->toDArray();

            return $this->transfer($request, $options);
        }

        throw new \RuntimeException("Invalid Request Options");
    }

    /**
     * Create and send an HTTP request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param string              $method  HTTP method.
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed> $options Request options to apply. See HackHttp\Client\RequestOptions.
     *
     * @throws \RuntimeException
     */
    public function request(string $method, mixed $uri = '', dict<arraykey,  mixed> $options = dict[]): ResponseInterface
    {
        $options[RequestOptions::SYNCHRONOUS] = true;

        $promise = $this->requestAsync($method, $uri, $options);
        $retval =  $promise->wait();
        if($retval is ResponseInterface) {
            return $retval;
        }

        throw new \RuntimeException("Response value is not a ResponseInterface");
    }

    private function buildUri(UriInterface $uri, dict<arraykey, mixed> $config): UriInterface
    {
        if (isset($config['base_uri'])) {
            $uri = UriResolver::resolve(HM\Utils::uriFor($config['base_uri']), $uri);
        }

        if (isset($config[RequestOptions::IDN_CONVERSION]) && ($config[RequestOptions::IDN_CONVERSION] !== false)) {
            $idnOptions = ($config[RequestOptions::IDN_CONVERSION] === true) ? \IDNA_DEFAULT : $config[RequestOptions::IDN_CONVERSION];
            if($idnOptions is int) {
                $uri = Utils::idnUriConvert($uri, $idnOptions);
            }
        }

        return $uri->getScheme() === '' && $uri->getHost() !== '' ? $uri->withScheme('http') : $uri;
    }

    /**
     * Configures the default options for a client.
     */
    private function configureDefaults(dict<arraykey, mixed> $config): void
    {
        $defaults = dict<string, mixed>[
            RequestOptions::ALLOW_REDIRECTS => RedirectMiddleware::$defaultSettings,
            RequestOptions::HTTP_ERRORS     => true,
            RequestOptions::DECODE_CONTENT  => true,
            RequestOptions::VERIFY          => true,
            RequestOptions::COOKIES         => false,
            RequestOptions::IDN_CONVERSION  => false,
        ];

        // Use the standard Linux HTTP_PROXY and HTTPS_PROXY if set.
        $proxy = Utils::getenv('HTTP_PROXY');
        if ($proxy is string && Str\length($proxy)) {
            $proxy_defaults = dict<string, mixed>[];
            $proxy_defaults['http'] = $proxy;
            $defaults[RequestOptions::PROXY] = $proxy_defaults;
        }

        $proxy = Utils::getenv('HTTPS_PROXY');
        if ($proxy is string && Str\length($proxy)) {
            $proxy_defaults = HH\idx($defaults, RequestOptions::PROXY);
            if(!($proxy_defaults is dict<_,_>)) {
                $proxy_defaults = dict<string, mixed>[];
            }
            $proxy_defaults['https'] = $proxy;
            $defaults[RequestOptions::PROXY] = $proxy_defaults;
        }

        $noProxy = Utils::getenv('NO_PROXY');
        if ($noProxy is string && Str\length($noProxy)) {
            $cleanedNoProxy = \str_replace(' ', '', $noProxy);
            $proxy_defaults = HH\idx($defaults, RequestOptions::PROXY);
            if(!($proxy_defaults is dict<_,_>)) {
                $proxy_defaults = dict<string, mixed>[];
            }
            $proxy_defaults['no'] =  \explode(',', $cleanedNoProxy);
            $defaults[RequestOptions::PROXY] = $proxy_defaults;
        }

        $this->config = Dict\merge($defaults, $config);

        if (HH\idx($config, RequestOptions::COOKIES) === true) {
            $this->config[RequestOptions::COOKIES] = new CookieJar();
        }

        // Add the default user-agent header.
        if (!isset($this->config[RequestOptions::HEADERS])) {
            $this->config[RequestOptions::HEADERS] = dict['User-Agent' => Utils::defaultUserAgent()];
        } else {
            // Add the User-Agent header if one was not already set.
            $headers = HH\idx($this->config, RequestOptions::HEADERS);
            if($headers is dict<_,_>) {
                foreach (\array_keys($headers) as $name) {
                    if ($name is string && \strtolower($name) === 'user-agent') {
                        return;
                    }
                }

                $headers['User-Agent'] = Utils::defaultUserAgent();;
                $this->config[RequestOptions::HEADERS] = $headers;
            }
           
            
        }
    }

    /**
     * Merges default options into the dict<arraykey, mixed>.
     *
     * @param dict<arraykey,  mixed> $options Options to modify by reference
     */
    private function prepareDefaults(dict<arraykey,  mixed> $options): dict<arraykey,  mixed>
    {
        $options = new Map($options);
        $defaults = new Map($this->config);

        if (HH\idx($defaults,RequestOptions::HEADERS) is nonnull) {
            // Default headers are only added if they are not present.
            $defaults['_conditional'] = $defaults[RequestOptions::HEADERS];
            $defaults->removeKey(RequestOptions::HEADERS);
        }

        // Special handling for headers is required as they are added as
        // conditional headers and as headers passed to a request ctor.
        if (C\contains_key($options, RequestOptions::HEADERS)) {
            // Allows default headers to be unset.
            if (HH\idx($options, RequestOptions::HEADERS) is null) {
                $defaults['_conditional'] = dict[];
                $options->removeKey(RequestOptions::HEADERS);
            } elseif (!(HH\idx($options, RequestOptions::HEADERS) is dict<_,_>)) {
                throw new \InvalidArgumentException('headers must be a dict<arraaykey, mixed>');
            }
        }

        // Shallow merge defaults underneath options.
        $result = new Map(Dict\merge($defaults, $options));

        // Remove null values.
        $null_value_keys = vec<arraykey>[];
        foreach ($result as $k => $v) {
            if ($v is null) {
                $null_value_keys[] = $k;
            }
        }

        foreach ($null_value_keys as $key) {
            $result->removeKey($key);
        }

        return $result->toDArray();
    }

    /**
     * Transfers the given request and applies request options.
     *
     * The URI of the request is not modified and the request options are used
     * as-is without merging in default options.
     * @param RequestInterface $request Request
     * @param dict<arraykey,  mixed> $options See HackHttp\Client\RequestOptions.
     */
    private function transfer(RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface
    {  
        try {
            $options_map = new Map($options);
            $request = $this->applyOptions($request, $options_map);
            $options = $options_map->toDArray();

            $handler = HH\idx($options,'handler');
            if($handler is RequestHandlerInterface) {
                $promise = $handler->handle($request, $options);
                return P\Create::promiseFor($promise);
            } else {
                return P\Create::rejectionFor(new \RuntimeException("Request handler is not a RequestHandlerInterface"));
            }
        } catch (\Exception $e) {
            return P\Create::rejectionFor($e);
        }
    }

    /**
     * Applies the dict<arraykey, mixed> of request options to a request.
     */
    private function applyOptions(RequestInterface $request, Map<arraykey,  mixed> $options): RequestInterface
    {
         $modify = dict['set_headers' => dict[]];

        if (isset($options[RequestOptions::HEADERS])) {
            $modify['set_headers'] = $options[RequestOptions::HEADERS];
            $options->removeKey(RequestOptions::HEADERS);
        }

        if (isset($options[RequestOptions::FORM_PARAMS])) {
            if (isset($options[RequestOptions::MULTIPART])) {
                throw new \ InvalidArgumentException('You cannot use '
                    . 'form_params and multipart at the same time. Use the '
                    . 'form_params option if you want to send application/'
                    . 'x-www-form-urlencoded requests, and the multipart '
                    . 'option to send multipart/form-data requests.');
            }
            $options[RequestOptions::BODY] = \http_build_query($options[RequestOptions::FORM_PARAMS], '', '&');
            $options->removeKey(RequestOptions::FORM_PARAMS);

            // Ensure that we don't have the header in different case and set the new value.

            $options_conditional = $options['_conditional'];
            if($options_conditional is dict<_,_>) {
                $options_conditional = HM\Utils::caselessRemove(vec['Content-Type'], $options_conditional);
            } else {
                $options_conditional = dict[];
            }
            $options_conditional['Content-Type'] = 'application/x-www-form-urlencoded';
            $options['_conditional'] = $options_conditional;
        }

        if (isset($options[RequestOptions::MULTIPART])) {
            $options_multipart = $options[RequestOptions::MULTIPART];
            if($options_multipart is vec<_>) {
                $options_multipart = HM\Utils::filterMultipart($options_multipart);
                $options[RequestOptions::BODY] = new MultipartStream($options_multipart);
                $options->removeKey(RequestOptions::MULTIPART);
            }
        }

        if (isset($options[RequestOptions::JSON])) {
            $options[RequestOptions::BODY] = Utils::jsonEncode($options[RequestOptions::JSON]);
            $options->removeKey(RequestOptions::JSON);
    
            // Ensure that we don't have the header in different case and set the new value.
            $options_conditional = $options['_conditional'];
            if($options_conditional is dict<_,_>) {
                $options_conditional = HM\Utils::caselessRemove(vec['Content-Type'], $options_conditional);
            } else {
                 $options_conditional = dict[];
            }
            $options_conditional['Content-Type'] = 'application/json';
            $options['_conditional'] = $options_conditional;
        }

        if (HH\idx($options,RequestOptions::DECODE_CONTENT) is nonnull && $options[RequestOptions::DECODE_CONTENT] !== true) {
            // Ensure that we don't have the header in different case and set the new value.
            $options_conditional = $options['_conditional'];
            if($options_conditional is dict<_,_>) {
                $options_conditional = HM\Utils::caselessRemove(vec['Accept-Encoding'], $options_conditional);
            } else {
                $options_conditional = dict[];
            }
            $modify_sh =HH\idx($modify, 'set_headers');
            if($modify_sh is dict<_,_>) {
                $modify_sh['Accept-Encoding'] = $options[RequestOptions::DECODE_CONTENT];
            }
            $modify['set_headers'] = $modify_sh;
            $options['_conditional'] = $options_conditional;
        }

        if (isset($options[RequestOptions::BODY])) {
            if (HH\is_any_array($options[RequestOptions::BODY])) {
                throw $this->invalidBody();
            }
            $modify[RequestOptions::BODY] =HM\Utils::streamFor($options[RequestOptions::BODY]);
            $options->removeKey(RequestOptions::BODY);
        }

        $value = HH\idx($options, RequestOptions::AUTH);
        if ($value is vec<_> && C\count($value) >= 2) {
            $value = HM\Utils::filterTraversable<string>($value);
            $type = C\count($value) > 2 ? \strtolower($value[2]) : 'basic';
            $username=$value[0];
            $password=$value[1];
            switch ($type) {
                case 'basic':
                    // Ensure that we don't have the header in different case and set the new value.
                    $modify_sh =HH\idx($modify, 'set_headers');
                    if($modify_sh is dict<_,_>) {
                        $modify_sh = HM\Utils::caselessRemove(vec['Authorization'], $modify_sh);
                    } else{
                        $modify_sh = dict[];
                    }
                    $modify_sh['Authorization'] = 'Basic '. \base64_encode("$username:$password");
                    $modify['set_headers'] = $modify_sh;
                    break;
                case 'digest':
                    $options_curl = HH\idx($options,'curl');
                    if(!($options_curl is dict<_,_>)) {
                        $options_curl  = dict[];
                    }
                    $options_curl[\CURLOPT_HTTPAUTH] = \CURLAUTH_DIGEST;
                    $options_curl[\CURLOPT_USERPWD] = "$username:$password";
                    $options['curl'] =  $options_curl;
                    break;
                case 'ntlm':
                    $options_curl = HH\idx($options,'curl');
                    if(!($options_curl is dict<_,_>)) {
                        $options_curl  = dict[];
                    }
                    $options_curl[\CURLOPT_HTTPAUTH] = \CURLAUTH_NTLM;
                    $options_curl[\CURLOPT_USERPWD] = "$username:$password";
                    $options['curl'] =  $options_curl;
                    break;
            }
        }

        $options_query = HH\idx($options, RequestOptions::QUERY);
        if ($options_query is nonnull) {
            $value = $options[RequestOptions::QUERY];
            if (HH\is_any_array($value)) {
                $value = \http_build_query($value, '', '&', \PHP_QUERY_RFC3986);
            }
            if (!($value is string)) {
                throw new \InvalidArgumentException('query must be a string, or array');
            }
            $modify[RequestOptions::QUERY] = $value;
            $options->removeKey(RequestOptions::QUERY);
        }

        // Ensure that sink is not an invalid value.
        if (isset($options[RequestOptions::SINK]) && $options[RequestOptions::SINK] is bool) {
            throw new \InvalidArgumentException('sink must not be a boolean');
        }

        $request = HM\Utils::modifyRequest($request, $modify);
        $request_body = $request->getBody();
        if ($request_body is MultipartStream) {
            // Use a multipart/form-data POST if a Content-Type is not set.
            // Ensure that we don't have the header in different case and set the new value.
            $options_conditional = $options['_conditional'];
            if($options_conditional is dict<_,_>) {
                $options_conditional = HM\Utils::caselessRemove(vec['Content-Type'], $options_conditional);
            } else {
                $options_conditional = dict[];
            }
            $options_conditional['Content-Type'] = 'multipart/form-data; boundary='. $request_body->getBoundary();
            $options['_conditional'] = $options_conditional;
        }

        // Merge in conditional headers if they are not present.
        $options_conditional = HH\idx($options, '_conditional');
        if ($options_conditional  is dict<_,_>) { 
            // Build up the changes so it's in a single clone of the message.
            $modify = dict[];
            $modify_sh = dict[];
            
            foreach ($options_conditional as $k => $v) {
                if ($k is string && !$request->hasHeader($k)) {
                    $modify_sh[$k] = $v;
                }
            }
            $modify['set_headers'] = $modify_sh;
            $request =HM\Utils::modifyRequest($request, $modify);
            // Don't pass this internal value along to middleware/handlers.
            $options->removeKey('_conditional');
        }

        return $request;
    }

    /**
     * Return an \ InvalidArgumentException with pre-set message.
     */
    private function invalidBody(): \InvalidArgumentException
    {
        return new \InvalidArgumentException('Passing in the "body" request '
            . 'option as an array to send a request is not supported. '
            . 'Please use the "form_params" request option to send a '
            . 'application/x-www-form-urlencoded request, or the "multipart" '
            . 'request option to send a multipart/form-data request.');
    }
}

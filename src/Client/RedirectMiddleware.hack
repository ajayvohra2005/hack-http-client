namespace HackHttp\Client;

use namespace HH;
use namespace HH\Lib\Dict;
use namespace HH\Lib\C;
use namespace HH\Lib\Vec;
use type HH\Map;
use HH\Lib\Str;

use namespace HackHttp\Message as HM;

use HackHttp\Client\Exception\BadResponseException;
use HackHttp\Client\Exception\TooManyRedirectsException;
use HackPromises\PromiseInterface;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\MessageInterface;
use HackHttp\Message\UriInterface;
use HackHttp\Message\UriResolver;
use HackHttp\Message\Uri;
use HackHttp\Message\Message;

/**
 * Request redirect middleware.
 *
 * Apply this middleware like other middleware using
 * {@see \HackHttp\Client\Middleware::redirect()}.
 *
 * @final
 */
class RedirectMiddleware
{
    const HISTORY_HEADER = 'X-Redirect-History';
    const STATUS_HISTORY_HEADER = 'X-Redirect-Status-History';

    /**
     * @var dict<string, mixed>
     */
    public static dict<string, mixed> $defaultSettings = dict[
        'max'             => 5,
        'protocols'       => vec['http', 'https'],
        'strict'          => false,
        'referer'         => false,
        'track_redirects' => false,
    ];

    /**
     * @var RequestHandlerCallable
     */
    private RequestHandlerCallable $nextHandler;

    /**
     * @param RequestHandlerCallable $nextHandler Next handler to invoke.
     */
    public function __construct(RequestHandlerCallable $nextHandler)
    {
        $this->nextHandler = $nextHandler;
    }

    public function redirect(RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface
    {
        $fn = $this->nextHandler;

        $options_allow_redirects = HH\idx($options, RequestOptions::ALLOW_REDIRECTS);

        if ($options_allow_redirects is null) {
            return $fn($request, $options);
        }

        if ($options_allow_redirects === true) {
            $options[RequestOptions::ALLOW_REDIRECTS] = self::$defaultSettings;
        } elseif ($options_allow_redirects is dict<_,_>) {
            // Merge the default settings with the provided settings
            $options[RequestOptions::ALLOW_REDIRECTS] = Dict\merge(self::$defaultSettings, $options_allow_redirects);
        } else {
            throw new \InvalidArgumentException('allow_redirects must be bool, or dict<string, mixed>');
        }

        if ($options_allow_redirects is dict<_,_> && !HH\idx($options_allow_redirects, 'max')) {
            return $fn($request, $options);
        }

        return $fn($request, $options)
            ->then( (mixed $response): mixed ==> {
                if($response is ResponseInterface) {
                    return $this->checkRedirect($request, $options, $response);
                }

                throw new \RuntimeException("response is not ResponseInterface");
            });
    }

    /**
     * @return mixed PromiseInterface or ResponseInterface
     */
    public function checkRedirect(RequestInterface $request, 
                    dict<arraykey,  mixed>  $options, 
                    ResponseInterface $response): mixed
    {
        if (Str\search((string) $response->getStatusCode(), '3') !== 0 || !$response->hasHeader('Location')) {
            return $response;
        }

        $options_map = new Map($options);
        $this->guardMax($request, $response, $options_map);
        $options = $options_map->toDArray();

        $nextRequest = $this->modifyRequest($request, $options, $response);

        $promise = $this->redirect($nextRequest, $options);

        // Add headers to be able to track history of redirects.
        $options_allow_redirects = HH\idx($options, RequestOptions::ALLOW_REDIRECTS);

        if ($options_allow_redirects is dict<_,_> &&
            HH\idx($options_allow_redirects, 'track_redirects')) {
            return $this->withTracking(
                $promise,
                $nextRequest->getUri()->__toString(),
                $response->getStatusCode()
            );
        }

        return $promise;
    }

    /**
     * Enable tracking on promise.
     */
    private function withTracking(PromiseInterface $promise, string $uri, int $statusCode): PromiseInterface
    {
        return $promise->then(
            (mixed $response) : mixed ==> {
                // Note that we are pushing to the front of the list as this
                // would be an earlier response than what is currently present
                // in the history header.
                if($response is ResponseInterface) {
                    $historyHeader = $response->getHeader(self::HISTORY_HEADER);
                    $statusHeader = $response->getHeader(self::STATUS_HISTORY_HEADER);
                    \array_unshift(inout $historyHeader, $uri);
                    \array_unshift(inout $statusHeader, (string) $statusCode);

                    $response_with_header = $response->withHeader(self::HISTORY_HEADER, $historyHeader);
                    if($response_with_header is ResponseInterface) {
                        return $response_with_header->withHeader(self::STATUS_HISTORY_HEADER, $statusHeader);
                    }
                    
                    throw new \RuntimeException("response with header is not a ResponseInterface");
                }

                throw new \RuntimeException("response is not a ResponseInterface");
            }
        );
    }

    /**
     * Check for too many redirects
     *
     * @throws TooManyRedirectsException Too many redirects.
     */
    private function guardMax(RequestInterface $request, ResponseInterface $response, 
        Map<arraykey,  mixed> $options): void
    {
        $current = $options['__redirect_count'] ?? 0;
        if($current is int) {
            $options['__redirect_count'] = $current + 1;
        }
        $options_allow_redirects = $options[RequestOptions::ALLOW_REDIRECTS];
        if($options_allow_redirects is dict<_,_>) {
            $max = $options_allow_redirects['max'];
            $options_redirect_count = $options['__redirect_count'];
            if ($options_redirect_count is int && $max is int && $options_redirect_count > $max) {
                throw new TooManyRedirectsException("Will not follow more than {$max} redirects", $request, $response);
            }
        }
    }

    public function modifyRequest(RequestInterface $request, 
                    dict<arraykey,  mixed> $options, 
                    ResponseInterface $response): RequestInterface
    {
        // Request modifications to apply.
        $modify = dict<string, mixed>[];

        $options_allow_redirects = $options[RequestOptions::ALLOW_REDIRECTS];

        $protocols = null;

        if($options_allow_redirects  is dict<_,_>) {
            $protocols = $options_allow_redirects['protocols'];
        
            // Use a GET request if this is an entity enclosing request and we are
            // not forcing RFC compliance, but rather emulating what all browsers
            // would do.
            $statusCode = $response->getStatusCode();
            if ($statusCode == 303 ||
                ($statusCode <= 302 && !HH\idx($options_allow_redirects, 'strict'))) {
                $safeMethods = vec['GET', 'HEAD', 'OPTIONS'];
                $requestMethod = $request->getMethod();

                $modify['method'] = C\contains($safeMethods, $requestMethod) ? $requestMethod : 'GET';
                $modify[RequestOptions::BODY] = '';
            }

            if($protocols is vec<_>) {
                $protocols = HM\Utils::filterTraversable<string>($protocols);

                $uri = $this->redirectUri($request, $response, $protocols);
                if (isset($options[RequestOptions::IDN_CONVERSION]) && ($options[RequestOptions::IDN_CONVERSION] !== false)) {
                    $idnOptions = ($options[RequestOptions::IDN_CONVERSION] === true) ? \IDNA_DEFAULT : $options[RequestOptions::IDN_CONVERSION];
                    if($idnOptions is int) {
                        $uri = Utils::idnUriConvert($uri, $idnOptions);
                    }
                }

                $modify['uri'] = $uri;
                Message::rewindBody($request);

                // Add the Referer header if it is told to do so and only
                // add the header if we are not redirecting from https to http.
                if (HH\idx($options_allow_redirects,'referer')
                    && $uri->getScheme() === $request->getUri()->getScheme()) {
                    $uri = $request->getUri()->withUserInfo('');
                    $modify_set_headers = dict[];
                    $modify_set_headers['Referer'] = $uri->__toString();
                    $modify['set_headers'] = $modify_set_headers;
                } else {
                    $modify_remove_headers = HH\idx($modify, 'remove_headers');
                    if(!($modify_remove_headers is vec<_>)) {
                        $modify_remove_headers = vec[];
                    }
                    $modify_remove_headers[] = 'Referer';
                    $modify['remove_headers'] = $modify_remove_headers;
                }

                // Remove Authorization header if host is different.
                if ($request->getUri()->getHost() !== $uri->getHost()) {
                    $modify_remove_headers = HH\idx($modify, 'remove_headers');
                    if(!($modify_remove_headers is vec<_>)) {
                        $modify_remove_headers = vec[];
                    }
                    $modify_remove_headers[] = 'Authorization';
                    $modify['remove_headers'] = $modify_remove_headers;
                }

                return HM\Utils::modifyRequest($request, $modify);
            } else {
                throw new \RuntimeException(" protocols is not a vec<string>");
            }

        } else {
            throw new \RuntimeException(" options[RequestOptions::ALLOW_REDIRECTS] is not a dict");
        }

        
    }

    /**
     * Set the appropriate URL on the request based on the location header
     */
    private function redirectUri(RequestInterface $request, 
                    ResponseInterface $response, 
                    vec<string> $protocols): UriInterface
    {
        $location = UriResolver::resolve(
            $request->getUri(),
            new Uri($response->getHeaderLine('Location'))
        );

        // Ensure that the redirect URI is allowed based on the protocols.
        if (!C\contains($protocols, $location->getScheme())) {
            throw new BadResponseException(\sprintf('Redirect URI, %s, does not use one of the allowed redirect protocols: %s', 
                $location->__toString(), \implode(', ', $protocols)), $request, $response);
        }

        return $location;
    }
}

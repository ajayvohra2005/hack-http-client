namespace HackHttp\Client;

use HackHttp\Client\Cookie\CookieJarInterface;
use HackHttp\Client\Exception\RequestException;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;
use HackPromises as P;
use HackPromises\PromiseInterface;

use namespace HH;

type MiddlewareFunction = ( function(RequestHandlerCallable ): RequestHandlerCallable);
type ResponseHandlerCallable = (function(RequestInterface, dict<arraykey,  mixed>, PromiseInterface): void);

/**
 * Functions used to create and wrap handlers with handler middleware.
 */
final class Middleware
{
    /**
     * Middleware that adds cookies to requests.
     *
     * @return (MiddlewareFunction
     */
    public static function cookies(): MiddlewareFunction
    {
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
            return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {

                $cookieJar = HH\idx($options,RequestOptions::COOKIES);

                if ( !$cookieJar) {
                    return $handler($request, $options);
                } elseif (!( $cookieJar  is CookieJarInterface)) {
                    throw new \InvalidArgumentException('cookies are not HackHttp\Client\Cookie\CookieJarInterface');
                }

                $request = $cookieJar->withCookieHeader($request);
                return $handler($request, $options)
                    ->then( (mixed $response): mixed  ==> {
                            if($response is ResponseInterface) {
                                $cookieJar->extractCookies($request, $response);
                                return $response;
                            }

                            throw new \RuntimeException("response is not ResponseInterface");
                        });
            };
        };
    }

    /**
     * Middleware that throws exceptions for 4xx or 5xx responses when the
     * "http_errors" request option is set to true.
     *
     * @param ?BodySummarizerInterface $bodySummarizer The body summarizer to use in exception messages.
     *
     * @return MiddlewareFunction Returns a function that accepts the next handler.
     */
    public static function httpErrors(?BodySummarizerInterface $bodySummarizer = null): MiddlewareFunction
    {
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
             return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
                $options_http_errors = HH\idx($options, RequestOptions::HTTP_ERRORS);

                if ($options_http_errors is null) {
                    return $handler($request, $options);
                }
                return $handler($request, $options)->then(
                    (mixed $response): mixed  ==> {
                        if($response is ResponseInterface) {
                            $code = $response->getStatusCode();
                            if ($code < 400) {
                                return $response;
                            }

                            throw RequestException::create($request, $response, null, dict[], $bodySummarizer);
                        }

                        throw new \RuntimeException("response is not ResponseInterface");
                    }
                );
            };
        };
    }

    /**
     * Middleware that pushes history data vec<dict<arraykey, mixed>>.
     *
     * @param inout dict<arraykey, mixed> $container Container to hold the history (by reference).
     *
     * @return MiddlewareFunction Returns a function that accepts the next handler.
     *
     * @throws \InvalidArgumentException if container is not an array or ArrayAccess.
     */
    public static function history(inout vec<dict<arraykey, mixed>> $container): MiddlewareFunction
    {
       
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
             return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
                return $handler($request, $options)->then(
                    (mixed $value): mixed ==> {
                        $container[] = dict[
                            'request'  => $request,
                            'response' => $value,
                            'error'    => null,
                            'options'  => $options
                        ];
                        return $value;
                    },
                    (mixed $reason): mixed ==> {
                        $container[] = dict[
                            'request'  => $request,
                            'response' => null,
                            'error'    => $reason,
                            'options'  => $options
                        ];
                        return P\Create::rejectionFor($reason);
                    }
                );
            };
        };
    }

    /**
     * Middleware that invokes a handler before and after sending a request.
     *
     * The provided listener cannot modify or alter the response. It simply
     * "taps" into the chain to be notified before returning the promise. The
     * before listener accepts a request and options array, and the after
     * listener accepts a request, options array, and response promise.
     *
     * @param ?RequestHandlerCallable $before Function to invoke before forwarding the request.
     * @param ?ResponseHandlerCallable $after  Function invoked after forwarding.
     *
     * @return MiddlewareFunction Returns a function that accepts the next handler.
     */
    public static function tap(?RequestHandlerCallable $before = null, ?ResponseHandlerCallable $after = null): MiddlewareFunction
    {
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
             return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
                if ($before is nonnull) {
                    $before($request, $options);
                }
                $response = $handler($request, $options);
                if ($after is nonnull) {
                    $after($request, $options, $response);
                }
                return $response;
            };
        };
    }

    /**
     * Middleware that handles request redirects.
     *
     * @return MiddlewareFunction Returns a function that accepts the next handler.
     */
    public static function redirect(): MiddlewareFunction
    {
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
            return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
                $redirect = new RedirectMiddleware($handler);
                return $redirect->redirect($request, $options);
            };
        };
    }

    /**
     * Middleware that retries requests based on the boolean result of
     * invoking the provided "decider" function.
     *
     * If no delay function is provided, a simple implementation of exponential
     * backoff will be utilized.
     *
     * @param DeciderFunction $decider Function that accepts the number of retries,
     *                          a request, [response], and [exception] and
     *                          returns true if the request is to be retried.
     * @param DelayFunction $delay   Function that accepts the number of retries and
     *                          returns the number of milliseconds to delay.
     *
     * @return MiddlewareFunction Returns a function that accepts the next handler.
     */
    public static function retry(DeciderFunction $decider, ?DelayFunction $delay = null): MiddlewareFunction
    {
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
            return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
                $retry = new RetryMiddleware($decider, $handler, $delay);
                return $retry->retry($request, $options);
            };
        };
    }

    /**
     * This middleware adds a default content-type if possible, a default
     * content-length or transfer-encoding header, and the expect header.
     */
    public static function prepareBody(): MiddlewareFunction
    {
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
            return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
                $prepare = new PrepareBodyMiddleware($handler);
                return $prepare->prepare($request, $options);
            };
        };
    }

    /**
     * Middleware that applies a map function to the request before passing to
     * the next handler.
     *
     * @param (function(RequestInterface): RequestInterface) $fn Function that accepts a RequestInterface and returns
     *                     a RequestInterface.
     */
    public static function mapRequest((function(RequestInterface): RequestInterface) $fn): MiddlewareFunction
    {
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
            return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
                return $handler($fn($request), $options);
            };
        };
    }

    /**
     * Middleware that applies a map function to the resolved promise's
     * response.
     *
     * @param (function(ResponseInterface): ResponseInterface)  $fn Function that accepts a ResponseInterface and
     *                     returns a ResponseInterface.
     */
    public static function mapResponse((function(ResponseInterface): ResponseInterface) $fn): MiddlewareFunction
    {
        return (RequestHandlerCallable $handler): RequestHandlerCallable ==> {
            return (RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface ==> {
                $then_cb = (mixed $value): mixed ==> {
                    if($value is ResponseInterface) {
                        return $fn($value);
                    }

                    throw new \RuntimeException("value is not a ResponseInterface");
                };
                return $handler($request, $options)->then($then_cb);
            };
        };
    }
}

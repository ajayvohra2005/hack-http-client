namespace HackHttp\Client\Handler;

use HackPromises\PromiseInterface;
use HackHttp\Client\RequestOptions;
use HackHttp\Message\RequestInterface;

use type HackHttp\Client\RequestHandlerCallable;
use namespace HH;

/**
 * Provides basic proxies for handlers.
 *
 * @final
 */
final class Proxy
{
    /**
     * Sends synchronous requests to a specific handler while sending all other
     * requests to another handler.
     *
     * @param RequestHandlerCallable $default Handler used for normal responses
     * @param RequestHandlerCallable $sync    Handler used for synchronous responses.
     *
     * @return RequestHandlerCallable Returns the composed handler.
     */
    public static function wrapSync(RequestHandlerCallable $default, RequestHandlerCallable $sync): RequestHandlerCallable
    {
        return (RequestInterface $request, dict<arraykey, mixed> $options): PromiseInterface ==> {
            $is_sync = HH\idx($options, RequestOptions::SYNCHRONOUS);
            return $is_sync ? $sync($request, $options) : $default($request, $options);
        };
    }
}

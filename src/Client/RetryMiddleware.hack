namespace HackHttp\Client;

use namespace HH;

use HackPromises as P;
use HackPromises\PromiseInterface;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;

type DeciderFunction = (function(int, RequestInterface, ?ResponseInterface, ?\Exception): bool);
type DelayFunction = (function(int): int);

/**
 * Middleware that retries requests based on the boolean result of
 * invoking the provided "decider" function.
 *
 * @final
 */
class RetryMiddleware
{
    /**
     * @var RequestHandlerCallable
     */
    private RequestHandlerCallable $nextHandler;

    /**
     * @var DeciderFunction
     */
    private DeciderFunction $decider;

    /**
     * @var DelayFunction
     */
    private DelayFunction $delay;

    /**
     * @param DeciderFunction  $decider  Function that accepts the number of retries,
     *                                   a request, [response], and [exception] and
     *                                   returns true if the request is to be retried.                                                                    
     * @param RequestHandlerCallable $nextHandler Next handler to invoke.
     * @param ?DelayFunction $delay  Function that accepts the number of retries
     *                               and returns the number of milliseconds to delay.                                                               
     */
    public function __construct(DeciderFunction $decider, 
                    RequestHandlerCallable $nextHandler, 
                    ?DelayFunction  $delay = null)
    {
        $this->decider = $decider;
        $this->nextHandler = $nextHandler;

        if($delay is nonnull) {
            $this->delay = $delay;
        } else {
            $this->delay = (int $retries): int ==> { return self::exponentialDelay($retries); };
        }
    }

    /**
     * Default exponential backoff delay function.
     * @param  int $retries number of retries
     * @return int milliseconds.
     */
    public static function exponentialDelay(int $retries): int
    {
        return (int) \pow(2, $retries - 1) * 1000;
    }

    public function retry(RequestInterface $request, dict<arraykey,  mixed> $options): PromiseInterface
    {
        if (!isset($options['retries'])) {
            $options['retries'] = 0;
        }

        $fn = $this->nextHandler;
        return $fn($request, $options)
            ->then(
                $this->onFulfilled($request, $options),
                $this->onRejected($request, $options)
            );
    }

    /**
     * Execute fulfilled closure
     * @return P\ThenCallback
     */
    private function onFulfilled(RequestInterface $request, dict<arraykey,  mixed> $options): P\ThenCallback
    {
        return (mixed $value): mixed ==> {
            $retries = HH\idx($options, 'retries');

            if ($retries is int && $value is ResponseInterface) {
                if (!($this->decider)(
                    $retries,
                    $request,
                    $value,
                    null)) {
                    return $value;
                }
                return $this->doRetry($request, $options, $value);
            } else {
                throw new \RuntimeException("options['retries'] must be int, and value must be a HackHttp\Message\ResponseInterface");
            }

        };
    }

    /**
     * Execute rejected closure
     */
    private function onRejected(RequestInterface $request, dict<arraykey,  mixed> $options): P\ThenCallback
    {

        return (mixed $reason): mixed ==> {
            $retries = HH\idx($options, 'retries');

            if ($retries is int && $reason is \Exception) {
                if (!($this->decider)(
                    $retries,
                    $request,
                    null,
                    $reason)) {
                    return P\Create::rejectionFor($reason);
                }
                return $this->doRetry($request, $options);
            } else {
                throw new \RuntimeException("options['retries'] must be int, and reason must be a \Exception");
            }

        };
    }

    private function doRetry(RequestInterface $request, dict<arraykey,  mixed> $options, ?ResponseInterface $response = null): PromiseInterface
    {
        $retries = HH\idx($options, 'retries');
        if($retries is int) {
            $options['retries'] = $retries + 1;
            $options[RequestOptions::DELAY] = ($this->delay)($retries + 1);

            return $this->retry($request, $options);
        }

        throw new \RuntimeException("options['retries'] must be int");
    }
}

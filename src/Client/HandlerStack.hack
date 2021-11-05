
namespace HackHttp\Client;

use namespace HH;
use namespace HH\Lib\Vec;

use HackHttp\Client\Promise\PromiseInterface;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;

type MiddlewareTuple = (MiddlewareFunction, string);
/**
 * Creates a composed  handler function by stacking middlewares on top of
 * an HTTP handler function.
 *
 * @final
 */
final class HandlerStack implements RequestHandlerInterface
{
    /**
     * @var ?RequestHandlerCallable
     */
    private ?RequestHandlerCallable $handler;

    /**
     * @var vec<MiddlewareStackElement>
     */
    private vec<MiddlewareTuple> $stack = vec[];

    /**
     * @var ?RequestHandlerCallable
     */
    private ?RequestHandlerCallable $cached;

    /**
     * Creates a default handler stack that can be used by clients.
     *
     * The returned handler will wrap the provided handler or use the most
     * appropriate default handler for your system. The returned HandlerStack has
     * support for cookies, redirects, HTTP error exceptions, and preparing a body
     * before sending.
     *
     * The returned handler stack can be passed to a client in the "handler"
     * option.
     *
     * @param ?RequestHandlerCallable $handler HTTP handler function to use with the stack. If no
     *                                          handler is provided, the best handler for your
     *                                          system will be utilized.
     */
    public static function create(?RequestHandlerCallable $handler = null): HandlerStack
    {
        $stack = new HandlerStack($handler ?: Utils::chooseHandler());
        $stack->push(Middleware::httpErrors(), RequestOptions::HTTP_ERRORS);
        $stack->push(Middleware::redirect(), RequestOptions::ALLOW_REDIRECTS);
        $stack->push(Middleware::cookies(), RequestOptions::COOKIES);
        $stack->push(Middleware::prepareBody(), 'prepare_body');

        return $stack;
    }

    /**
     * @param ?RequestHandlerCallable $handler Underlying HTTP handler.
     */
    public function __construct(?RequestHandlerCallable $handler = null)
    {
        $this->handler = $handler;
    }

    /**
     * Handle the request by using the the handler stack as a composed handler
     *
     * @param RequestInterface $request
     * @param dict<arraykey,  mixed> $options request options
     * @return mixed A ResponseInterface, or a PromiseInterface
     */
    public function handle(RequestInterface $request, dict<arraykey,  mixed> $options): mixed
    {
        $handler = $this->resolve();
        return $handler($request, $options);
    }

    /**
     * Set the HTTP handler that actually returns a promise.
     *
     * @param RequestHandlerCallable $handler Accepts a request and array of options and
     *                                                                     returns a Promise.
     */
    public function setHandler(RequestHandlerCallable $handler): void
    {
        $this->handler = $handler;
        $this->cached = null;
    }

    /**
     * Returns true if the builder has a handler.
     */
    public function hasHandler(): bool
    {
        return $this->handler is nonnull ;
    }

    /**
     * Unshift a middleware to the bottom of the stack.
     *
     * @param MiddlewareFunction $middleware Middleware function
     * @param string  $name       Name to register for this middleware.
     */
    public function unshift(MiddlewareFunction $middleware, string $name=''): void
    {
        $this->stack = Vec\concat(vec[tuple($middleware, $name)], $this->stack);
        $this->cached = null;
    }

    /**
     * Push a middleware to the top of the stack.
     *
     * @param MiddlewareFunction $middleware Middleware function
     * @param string    $name       Name to register for this middleware.
     */
    public function push(MiddlewareFunction $middleware, string $name=''): void
    {
        $this->stack[] = tuple($middleware, $name);
        $this->cached = null;
    }

    /**
     * Add a middleware before another middleware by name.
     *
     * @param string             $findName   Middleware to find
     * @param MiddlewareFunction $middleware Middleware function
     * @param string             $withName   Name to register for this middleware.
     */
    public function before(string $findName, MiddlewareFunction $middleware, string $withName = ''): void
    {
        $this->splice($findName, $withName, $middleware, true);
    }

    /**
     * Add a middleware after another middleware by name.
     *
     * @param string             $findName   Middleware to find
     * @param MiddlewareFunction $middleware Middleware function
     * @param string             $withName   Name to register for this middleware.
     */
    public function after(string $findName, MiddlewareFunction $middleware, string $withName = ''): void
    {
        $this->splice($findName, $withName, $middleware, false);
    }

    /**
     * Remove a middleware by instance or name from the stack.
     *
     * @param mixed $remove Middleware function to remove by instance or name.
     */
    public function remove(mixed $remove): void
    {
        $remove_pred = null;

        if($remove is string) {
            $remove_pred = (MiddlewareTuple $tup): bool ==> {
                if($tup[1] !== $remove) {
                    return true;
                } else {
                    return false;
                }
            };
        } else {
            $remove_pred = (MiddlewareTuple $tup): bool ==> {
                if($tup[0] !== $remove) {
                    return true;
                } else {
                    return false;
                }
            };
        }
        if($remove_pred) {
            $this->stack = Vec\filter($this->stack, $remove_pred );
            $this->cached = null;
        }

        throw new \RuntimeException("remove is not a Middleware funciton name or instance");
    }

    /**
     * Compose the middleware and handler into a single callable function.
     *
     * @return callable(RequestInterface, array): PromiseInterface
     */
    public function resolve(): RequestHandlerCallable
    {
        if ($this->cached === null) {
            $prev = $this->handler;
            if ($prev is null) {
                throw new \LogicException('No handler has been specified');
            }

            foreach (\array_reverse($this->stack) as $fn) {
                /** @var callable(RequestInterface, array): PromiseInterface $prev */
                $prev = $fn[0]($prev);
            }

            $this->cached = $prev;
        }

        return $this->cached;
    }

    private function findByName(string $name): int
    {
        foreach ($this->stack as $k => $v) {
            if ($v[1] === $name) {
                return $k;
            }
        }

        throw new \InvalidArgumentException("Middleware not found: $name");
    }

    /**
     * Splices a function into the middleware list at a specific position.
     */
    private function splice(string $findName, string $withName, MiddlewareFunction $middleware, bool $before): void
    {
        $this->cached = null;
        $idx = $this->findByName($findName);
        $tuple = tuple($middleware, $withName);

        if ($before) {
            if ($idx === 0) {
                $this->stack = Vec\concat(vec[$tuple], $this->stack);
            } else {
                $this->stack = Vec\concat(
                    Vec\concat(Vec\take($this->stack, $idx), vec[$tuple]), 
                    Vec\drop($this->stack, $idx) );
            }
        } elseif ($idx === \count($this->stack) - 1) {
            $this->stack[] = $tuple;
        } else {
            $this->stack = Vec\concat(
                    Vec\concat(Vec\take($this->stack, $idx+1), vec[$tuple]), 
                    Vec\drop($this->stack, $idx+1) );
        }
    }

}

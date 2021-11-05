namespace HackHttp\Client;

use namespace HH;
use namespace HH\Lib\C;
use namespace HH\Lib\Vec;

use type HackPromises\PromiseInterface;
use type HackHttp\Message\RequestInterface;

type RequestHandlerCallable = (function(RequestInterface, dict<arraykey,  mixed>): PromiseInterface);

interface RequestHandlerInterface
{

    /**
     * Handle the request
     *
     * @param RequestInterface $request
     * @param dict<arraykey,  mixed> $options request options
     * @return mixed A ResponseInterface, or a PromiseInterface
     */
    public function handle(RequestInterface $request, dict<arraykey,  mixed> $options): mixed;
    
} 
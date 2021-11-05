namespace HackHttp\Client\Handler;

use HackHttp\Message\RequestInterface;

interface CurlFactoryInterface
{
    /**
     * Creates a cURL handle resource.
     *
     * @param RequestInterface $request Request
     * @param dict<arraykey, mixed>            $options Transfer options
     *
     * @throws \RuntimeException when an option cannot be applied
     */
    public function create(RequestInterface $request, dict<arraykey, mixed> $options): EasyHandle;

    /**
     * Release an easy handle, allowing it to be reused or closed.
     *
     * This function must call unset on the easy handle's "handle" property.
     */
    public function release(EasyHandle $easy): void;
}

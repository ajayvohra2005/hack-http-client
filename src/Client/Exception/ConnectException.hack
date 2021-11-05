
namespace HackHttp\Client\Exception;

use HackHttp\Client\AbstractNetworkException;
use HackHttp\Message\RequestInterface;

/**
 * Exception thrown when a connection cannot be established.
 *
 * Note that no response is present for a ConnectException
 */
class ConnectException extends AbstractNetworkException
{
    /**
     * @var RequestInterface
     */
    private RequestInterface $request;

    /**
     * @var array
     */
    private dict<arraykey, mixed> $handlerContext;

    public function __construct(
        string $message,
        RequestInterface $request,
        ?\Exception $previous = null,
        dict<arraykey, mixed> $handlerContext = dict[]
    ) {
        parent::__construct($message, 0, $previous);
        $this->request = $request;
        $this->handlerContext = $handlerContext;
    }

    /**
     * Get the request that caused the exception
     */
    public function getRequest(): RequestInterface
    {
        return $this->request;
    }

    /**
     * Get contextual information about the error from the underlying handler.
     *
     * The contents of this array will vary depending on which handler you are
     * using. It may also be just an empty array. Relying on this data will
     * couple you to a specific handler, but can give more debug information
     * when needed.
     */
    public function getHandlerContext(): dict<arraykey, mixed>
    {
        return $this->handlerContext;
    }
}

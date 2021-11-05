namespace HackHttp\Client\Exception;

use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;

/**
 * Exception when an HTTP error occurs (4xx or 5xx error)
 */
class BadResponseException extends RequestException
{
    public function __construct(
        string $message,
        RequestInterface $request,
        ResponseInterface $response,
        ?\Exception $previous = null,
        dict<arraykey, mixed> $handlerContext = dict[]
    ) {
        parent::__construct($message, $request, $response, $previous, $handlerContext);
    }

    /**
     * Current exception and the ones that extend it will always have a response.
     */
    public function hasResponse(): bool
    {
        return true;
    }

    /**
     * This function narrows the return type from the parent class and does not allow it to be nullable.
     */
    public function getResponse(): ?ResponseInterface
    {
        /** @var ResponseInterface */
        return parent::getResponse();
    }
}

namespace HackHttp\Client;

use HackHttp\Message\RequestInterface;

/**
 * Exception for when a request failed.
 *
 * Examples:
 *      - Request is invalid (e.g. method is missing)
 *      - Runtime request errors (e.g. the body stream is not seekable)
 */
abstract class AbstractRequestException extends AbstractTransferException
{
    /**
     * Returns the request.
     * @return RequestInterface
     */
    public abstract function getRequest(): RequestInterface;
}

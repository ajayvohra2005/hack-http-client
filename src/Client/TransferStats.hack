
namespace HackHttp\Client;

use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\UriInterface;

/**
 * Represents data at the point after it was transferred either successfully
 * or after a network error.
 */
final class TransferStats
{
    /**
     * @var RequestInterface
     */
    private RequestInterface $request;

    /**
     * @var ?ResponseInterface
     */
    private ?ResponseInterface $response;

    /**
     * @var ?float
     */
    private ?float $transferTime;

    /**
     * @var dict<arraykey, mixed>
     */
    private dict<arraykey, mixed> $handlerStats;

    /**
     * @var mixed
     */
    private mixed $handlerErrorData;

    /**
     * @param RequestInterface       $request          Request that was sent.
     * @param ?ResponseInterface $response         Response received (if any)
     * @param ?float             $transferTime     Total handler transfer time.
     * @param mixed                  $handlerErrorData Handler error data.
     * @param dict<arraykey, mixed>                  $handlerStats     Handler specific stats.
     */
    public function __construct(
        RequestInterface $request,
        ?ResponseInterface $response = null,
        ?float $transferTime = null,
        mixed $handlerErrorData = null,
        dict<arraykey, mixed> $handlerStats = dict[]
    ) {
        $this->request = $request;
        $this->response = $response;
        $this->transferTime = $transferTime;
        $this->handlerErrorData = $handlerErrorData;
        $this->handlerStats = $handlerStats;
    }

    public function getRequest(): RequestInterface
    {
        return $this->request;
    }

    /**
     * Returns the response that was received (if any).
     */
    public function getResponse(): ?ResponseInterface
    {
        return $this->response;
    }

    /**
     * Returns true if a response was received.
     */
    public function hasResponse(): bool
    {
        return $this->response !== null;
    }

    /**
     * Gets handler specific error data.
     *
     * This might be an exception, a integer representing an error code, or
     * anything else. Relying on this value assumes that you know what handler
     * you are using.
     *
     * @return mixed
     */
    public function getHandlerErrorData(): mixed
    {
        return $this->handlerErrorData;
    }

    /**
     * Get the effective URI the request was sent to.
     */
    public function getEffectiveUri(): UriInterface
    {
        return $this->request->getUri();
    }

    /**
     * Get the estimated time the request was being transferred by the handler.
     *
     * @return float|null Time in seconds.
     */
    public function getTransferTime(): ?float
    {
        return $this->transferTime;
    }

    /**
     * Gets an dict<arraykey, mixed> of all of the handler specific transfer data.
     */
    public function getHandlerStats(): dict<arraykey, mixed>
    {
        return $this->handlerStats;
    }

    /**
     * Get a specific handler statistic from the handler by name.
     *
     * @param string $stat Handler specific transfer stat to retrieve.
     *
     * @return mixed
     */
    public function getHandlerStat(string $stat): mixed
    {
        return $this->handlerStats[$stat] ?? null;
    }
}

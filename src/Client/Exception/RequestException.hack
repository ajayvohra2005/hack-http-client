namespace HackHttp\Client\Exception;

use HH\Lib\Str;

use HackHttp\Client\BodySummarizer;
use HackHttp\Client\BodySummarizerInterface;
use HackHttp\Client\AbstractRequestException;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\UriInterface;

/**
 * HTTP Request exception
 */
class RequestException extends AbstractRequestException
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
     * @var dict<arraykey, mixed>
     */
    private dict<arraykey, mixed> $handlerContext;

    public function __construct(
        string $message,
        RequestInterface $request,
        ?ResponseInterface $response = null,
        ?\Exception $previous = null,
        dict<arraykey, mixed> $handlerContext = dict[]
    ) {
        // Set the code of the exception if the response is set and not future.
        $code = $response ? $response->getStatusCode() : 0;
        parent::__construct($message, $code, $previous);
        $this->request = $request;
        $this->response = $response;
        $this->handlerContext = $handlerContext;
    }

    /**
     * Wrap non-RequestExceptions with a RequestException
     */
    public static function wrapException(RequestInterface $request, \Exception $e): RequestException
    {
        return $e is RequestException ? $e : new RequestException($e->getMessage(), $request, null, $e);
    }

    /**
     * Factory method to create a new exception with a normalized error message
     *
     * @param RequestInterface             $request        Request sent
     * @param ResponseInterface            $response       Response received
     * @param ?\Exception              $previous       Previous exception
     * @param dict<arraykey, mixed>                        $handlerContext Optional handler context
     * @param ?BodySummarizerInterface $bodySummarizer Optional body summarizer
     */
    public static function create(
        RequestInterface $request,
        ?ResponseInterface $response = null,
        ?\Exception $previous = null,
        dict<arraykey, mixed> $handlerContext = dict[],
        ?BodySummarizerInterface $bodySummarizer = null): RequestException 
    {
        if (!$response) {
            return new RequestException(
                'Error completing request',
                $request,
                null,
                $previous,
                $handlerContext
            );
        }

        $level = (int) \floor($response->getStatusCode() / 100);
        if ($level === 4) {
            $label = 'Client error';
            $className = ClientException::class;
        } elseif ($level === 5) {
            $label = 'Server error';
            $className = ServerException::class;
        } else {
            $label = 'Unsuccessful request';
            $className = __CLASS__;
        }

        $uri = $request->getUri();
        $uri = self::obfuscateUri($uri);

        // Client Error: `GET /` resulted in a `404 Not Found` response:
        // <html> ... (truncated)
        $message = \sprintf(
            '%s: `%s %s` resulted in a `%s %s` response',
            $label,
            $request->getMethod(),
            $uri->__toString(),
            $response->getStatusCode(),
            $response->getReasonPhrase()
        );

        $summary = ($bodySummarizer ?? new BodySummarizer())->summarize($response);

        if ($summary !== null) {
            $message .= ":\n{$summary}\n";
        }

        switch ($className) {
            case ClientException::class:
               return new ClientException($message, $request, $response, $previous, $handlerContext);

            case ServerException::class:
                return new ServerException($message, $request, $response, $previous, $handlerContext);
            
            default:
                return new RequestException($message, $request, $response, $previous, $handlerContext);
        }

    }

    /**
     * Obfuscates URI if there is a username and a password present
     */
    private static function obfuscateUri(UriInterface $uri): UriInterface
    {
        $userInfo = $uri->getUserInfo();

        $pos = Str\search($userInfo, ':');
        if ($pos is int) {
            return $uri->withUserInfo(Str\slice($userInfo, 0, $pos), '***');
        }

        return $uri;
    }

    /**
     * Get the request that caused the exception
     */
    public function getRequest(): RequestInterface
    {
        return $this->request;
    }

    /**
     * Get the associated response
     */
    public function getResponse(): ?ResponseInterface
    {
        return $this->response;
    }

    /**
     * Check if a response was received
     */
    public function hasResponse(): bool
    {
        return $this->response is nonnull;
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

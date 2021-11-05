namespace HackHttp\Client\Handler;

use namespace HH;

use namespace HackHttp\Message as HM;

use HackHttp\Message\Response;
use HackHttp\Client\Utils;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\StreamInterface;
use HackHttp\Client\RequestOptions;

/**
 * Represents a cURL easy handle and the data it populates.
 *
 * @internal
 */
final class EasyHandle
{
    /**
     * @var resource a cURL handle
     */
    private ?resource $handle;

    /**
     * @var StreamInterface Where data is being written
     */
    private ?StreamInterface $sink;

    /**
     * @var vec<string> Received HTTP headers so far
     */
    private vec<string> $headers = vec[];

    /**
     * @var ?ResponseInterface Received response (if any)
     */
    private ?ResponseInterface $response;

    /**
     * @var RequestInterface Request being sent
     */
    private RequestInterface $request;

    /**
     * @var dict<arraykey, mixed> Request options
     */
    private dict<arraykey, mixed> $options;

    /**
     * @var int cURL error number (if any)
     */
    private int $errno = 0;

    /**
     * @var \Exception during on_headers (if any)
     */
    private ?\Exception $onHeadersException;

    /**
     * @var \Exception Exception during createResponse (if any)
     */
    private ?\Exception $createResponseException;

    public function __construct(RequestInterface $request, dict<arraykey, mixed> $options, 
        ?ResponseInterface $response=null)
    {
        $this->request = $request;
        $this->options = $options;
        $this->response = $response;
    }

    public function addHeader(string $h): void
    {
        $this->headers[] = $h;
    }
    
    public function setSink(StreamInterface $sink): void
    {
        $this->sink = $sink;
    }

    public function getSink(): ?StreamInterface
    {
        return $this->sink;
    }

    public function getHeaders(): vec<string>
    {
        return $this->headers;
    }

    public function getCreateResponseException(): ?\Exception
    {
        return $this->createResponseException;
    }

    public function setCreateResponseException(\Exception $e): void
    {
        $this->createResponseException = $e;
    }

    public function getOnHeadersException(): ?\Exception
    {
        return $this->onHeadersException;
    }

     public function setOnHeadersException(\Exception $e): void
    {
        $this->onHeadersException = $e;
    }

    public function getHandle(): ?resource
    {
        return $this->handle;
    }

    public function setHandle(?resource $handle): void
    {
        $this->handle = $handle;
    }

    public function getRequest(): RequestInterface
    {
        return $this->request;
    }
    
    public function setErrno(int $errno): void
    {
        $this->errno = $errno;
    }

    public function getErrno(): int
    {
        return $this->errno;
    }
    
    public function getResponse(): ?ResponseInterface
    {
        return $this->response;
    }

    public function getOptions(): dict<arraykey, mixed>
    {
        return $this->options;
    }
    
    public function getOption(arraykey $key): mixed
    {
        return HH\idx($this->options, $key);
    }
    
    public function setOption(arraykey $key, mixed $value): void
    {
        $this->options[$key] = $value;
    }

    public function delay(): float
    {
        $delay = 0.0;
        $value = HH\idx($this->options, RequestOptions::DELAY);
        if($value is num) {
            $delay = (float)$value;
        }

        return $delay;
    }

    /**
     * Attach a response to the easy handle based on the received headers.
     *
     * @throws \RuntimeException if no headers have been received or the first
     *                           header line is invalid.
     */
    public function createResponse(): void
    {
        $parsed_headers = HeaderProcessor::parseHeaders($this->headers);
        $ver = $parsed_headers[0];
        $status = $parsed_headers[1];
        $reason = $parsed_headers[2];
        $headers = $parsed_headers[3];
        
        if($headers is dict<_,_>) {
            $headers = HM\Utils::filterDictStringKeys($headers);
            $headers_map = new Map<string, mixed>($headers);
            $normalizedKeys = Utils::normalizeHeaderKeys($headers);

            $options_decode_content = HH\idx($this->options,RequestOptions::DECODE_CONTENT);

            if ($options_decode_content && isset($normalizedKeys['content-encoding'])) {

                $normalizedKeys_content_encoding = HH\idx($normalizedKeys, 'content-encoding');

                if($normalizedKeys_content_encoding is string) {
                    $headers_map['x-encoded-content-encoding'] = $headers[$normalizedKeys_content_encoding];
                    $headers_map->removeKey($normalizedKeys_content_encoding);

                    if (isset($normalizedKeys['content-length'])) {
                        $normalizedKeys_content_length = $normalizedKeys['content-length'];
                        if($normalizedKeys_content_length is string) {
                            $headers_map['x-encoded-content-length'] = $headers[$normalizedKeys_content_length];

                            if($this->sink is nonnull) {
                                $bodyLength = (int) $this->sink->getSize();
                                if ($bodyLength) {
                                    $headers_map[$normalizedKeys_content_length] = $bodyLength;
                                } else {
                                    $headers_map->removeKey($normalizedKeys_content_length);
                                }
                            }
                        }
                    }
                }
            }

            // Attach a response to the easy handle with the parsed headers.
            if($status is int && $ver is string && $reason is ?string) {
                $headers = HM\Utils::filterHeaders($headers_map->toDArray());
                $this->response = new Response(
                    $status,
                    $headers,
                    $this->sink,
                    $ver,
                    $reason
                );
            }
        } else {
            throw new \RuntimeException("headers is not a dict<_,_>");
        }

        
    }
}

namespace HackHttp\Message;

use HH\Lib\Dict;
use type HH\Map;

use InvalidArgumentException;

/**
 * request implementation.
 */
class Request implements RequestInterface
{
    use MessageTrait;

    /** @var string */
    private string $method;

    /** @var ?string */
    private ?string $requestTarget;

    /** @var UriInterface */
    private UriInterface $uri;

    /**
     * @param string  $method  HTTP method
     * @param nonnull    $uri     A string, or a UriInterface
     * @param dict<string, vec<string>>       $headers Request headers, key is string, and value is a  vec<string>
     * @param mixed  $body    Request body is a StreamInterface, a string, or null
     * @param string  $version Protocol version
     */
    public function __construct(
        string $method,
        nonnull $uri,
        dict<string, vec<string>> $headers = dict[],
        mixed $body = null,
        string $version = '1.1'
    ) {
        $this->assertMethod($method);
        if ($uri is string) {
            $this->uri = new Uri($uri);
        } elseif( $uri is UriInterface) {
            $this->uri = $uri;
        } else {
            throw new \RuntimeException("Uri must be a string or a UriInterface");
        }

        $this->method = \strtoupper($method);
        $this->setHeaders($headers);
        $this->protocol = $version;

        if (!\isset($this->headerNames['host'])) {
            $this->updateHostFromUri();
        }

        if ($body is nonnull  && $body !== '') {
            $this->stream = Utils::streamFor($body);
        }
    }

    public function getRequestTarget(): string
    {
        if ($this->requestTarget !== null) {
            return $this->requestTarget;
        }

        $target = $this->uri->getPath();
        if ($target === '') {
            $target = '/';
        }
        if ($this->uri->getQuery() != '') {
            $target .= '?' . $this->uri->getQuery();
        }

        return $target;
    }

    public function withRequestTarget(string $requestTarget): RequestInterface
    {
        if ( \preg_match('#\s#', $requestTarget)) {
            throw new InvalidArgumentException(
                'Invalid request target provided; cannot contain whitespace'
            );
        }

        $new = clone $this;
        $new->requestTarget = $requestTarget;
        return $new;
    }

    public function getMethod(): string
    {
        return $this->method;
    }

    public function withMethod(string $method): RequestInterface
    {
        $this->assertMethod($method);
        $new = clone $this;
        $new->method = \strtoupper($method);
        return $new;
    }

    public function getUri(): UriInterface
    {
        return $this->uri;
    }

    public function withUri(UriInterface $uri, bool $preserveHost = false): RequestInterface
    {
        if ($uri === $this->uri) {
            return $this;
        }

        $new = clone $this;
        $new->uri = $uri;

        if (!$preserveHost || !isset($this->headerNames['host'])) {
            $new->updateHostFromUri();
        }

        return $new;
    }

    private function updateHostFromUri(): void
    {
        $host = $this->uri->getHost();

        if ($host == '') {
            return;
        }

        $port = $this->uri->getPort();
        if ($port is nonnull) {
            $host .= ':' . $port;
        }

        if (isset($this->headerNames['host'])) {
            $header = $this->headerNames['host'];
        } else {
            $header = 'Host';
            $this->headerNames['host'] = 'Host';
        }
        
        // Ensure Host is the first header.
        // See: http://tools.ietf.org/html/rfc7230#section-5.4
        $headers = new Map($this->headers);
        $headers->removeKey($header);
        $this->headers = Dict\merge(dict[$header => vec[$host]], $headers->toDArray());
    }

    /**
     * @param string $method
     */
    private function assertMethod(string $method): void
    {
        if ($method === '') {
            throw new InvalidArgumentException('Method must be a non-empty string.');
        }
    }
}

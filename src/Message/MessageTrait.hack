namespace HackHttp\Message;

use namespace HH\Lib\Dict;
use namespace HH\Lib\Vec;
use HH\Map;

/**
 * Trait implementing functionality common to requests and responses.
 */
trait MessageTrait implements MessageInterface
{
    /** @var dict<string, vec<string>> Map of all registered headers, as original name => array of values */
    private dict<string, vec<string>> $headers = dict[];

    /** @var dict<string, string> Map of lowercase header name => original name at registration */
    private dict<string, string> $headerNames  = dict[];

    /** @var string */
    private string $protocol = '1.1';

    /** @var ?StreamInterface */
    private ?StreamInterface $stream;

    public function getProtocolVersion(): string
    {
        return $this->protocol;
    }

    public function withProtocolVersion(string $version): MessageInterface
    {
        if ($this->protocol === $version) {
            return $this;
        }

        $new = clone $this;
        $new->protocol = $version;
        return $new;
    }

    public function getHeaders(): dict<string, vec<string>>
    {
        return $this->headers;
    }

    public function hasHeader(string $header): bool
    {
        return isset($this->headerNames[\strtolower($header)]);
    }

    public function getHeader(string $header): vec<string>
    {
        $header = \strtolower($header);

        if (!isset($this->headerNames[$header])) {
            return vec[];
        }

        $header = $this->headerNames[$header];

       return $this->headers[$header];
    }

    public function getHeaderLine(string $header): string
    {
        return \implode(', ', $this->getHeader($header));
    }

    public function withHeader(string $header, vec<string> $value): mixed
    {
        $this->assertHeader($header);
        $value = $this->normalizeHeaderValue($value);
        $normalized = \strtolower($header);

        $new = clone $this;
        if (isset($new->headerNames[$normalized])) {
            $k = $new->headerNames[$normalized];
            $new->headers = (new Map($new->headers))->removeKey($k)->toDArray();
        }
        $new->headerNames[$normalized] = $header;
        $new->headers[$header] = $value;

        return $new;
    }

    public function withAddedHeader(string $header, vec<string> $value): MessageInterface
    {
        $this->assertHeader($header);
        $value = $this->normalizeHeaderValue($value);
        $normalized = \strtolower($header);

        $new = clone $this;
        if (isset($new->headerNames[$normalized])) {
            $header = $this->headerNames[$normalized];
            $new->headers[$header] = vec(\array_merge($this->headers[$header], $value));
        } else {
            $new->headerNames[$normalized] = $header;
            $new->headers[$header] = $value;
        }

        return $new;
    }

    public function withoutHeader(string $header): MessageInterface
    {
        $normalized = \strtolower($header);

        if (!isset($this->headerNames[$normalized])) {
            return $this;
        }

        $header = $this->headerNames[$normalized];

        $new = clone $this;

        $filter_cb = (string $v): bool ==> $v !== $header;
        $new->headers = Dict\filter_keys($this->headers, $filter_cb);
        
        $filter_cb = (string $v): bool ==> $v !== $normalized;
        $new->headerNames = Dict\filter_keys($this->headerNames, $filter_cb);

        return $new;
    }

    public function getBody(): StreamInterface
    {
        if (!$this->stream) {
            $this->stream = Utils::streamFor('');
        }

        return $this->stream;
    }

    public function withBody(StreamInterface $body): MessageInterface
    {
        if ($body === $this->stream) {
            return $this;
        }

        $new = clone $this;
        $new->stream = $body;
        return $new;
    }

    /**
     * @param dict<string, vec<string>> $headers
     */
    private function setHeaders(dict<string, vec<string>> $headers): void
    {
        $this->headerNames =  dict[];
        $this->headers = dict[];
        foreach ($headers as $header => $value) {
            if($header is string) {
                $this->assertHeader($header);
                $value = $this->normalizeHeaderValue($value);
                $normalized = \strtolower($header);
                if (isset($this->headerNames[$normalized])) {
                    $header = $this->headerNames[$normalized];
                    $this->headers[$header] = vec(\array_merge($this->headers[$header], $value));
                } else {
                    $this->headerNames[$normalized] = $header;
                    $this->headers[$header] = $value;
                }
            }
        }
    }

    /**
     * @param vec<string> $value $value
     *
     * @return vec<string>
     */
    private function normalizeHeaderValue(vec<string> $value): vec<string>
    {
        if (\count($value) === 0) {
            throw new \InvalidArgumentException('Header value can not be an empty array.');
        }

        return $this->trimHeaderValues($value);
    }

    /**
     * Trims whitespace from the header values.
     *
     * @param vec<string> $values Header values
     *
     * @return vec<string> Trimmed header values
     *
     * @see https://tools.ietf.org/html/rfc7230#section-3.2.4
     */
    private function trimHeaderValues(vec<string> $values): vec<string>
    {
        $map_cb = (string $v): string ==> \trim((string)$v, " \t");
        return Vec\map($values, $map_cb);
    }

    /**
     * @see https://tools.ietf.org/html/rfc7230#section-3.2
     *
     * @param string $header
     */
    private function assertHeader(string $header): void
    {
        if ( ! \preg_match('/^[a-zA-Z0-9\'`#$%&*+.^_|~!-]+$/', $header)) {
            throw new \InvalidArgumentException(\sprintf('"%s" is not valid header name',$header));
        }
    }
}

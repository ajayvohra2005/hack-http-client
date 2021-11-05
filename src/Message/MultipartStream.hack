namespace HackHttp\Message;

use HH;

/**
 * Stream that when read returns bytes for a streaming multipart or
 * multipart/form-data stream.
 */
final class MultipartStream implements StreamInterface
{
    use StreamDecoratorTrait;

    /** @var string */
    private string $boundary;

    /**
     * @param vec<dict<string, mixed>>  $elements vec of dict<string, mixed>, 
     *                         each dict containing a
     *                         required "name" key mapping to the form field,
     *                         name, a required "contents" key mapping to a
     *                         StreamInterface/resource/string, an optional
     *                         "headers" associative array of custom headers,
     *                         and an optional "filename" key mapping to a
     *                         string to send as the filename in the part.
     * @param ?string $boundary You can optionally provide a specific boundary
     *
     * @throws \InvalidArgumentException
     */
    public function __construct(vec<dict<string, mixed>> $elements = vec[], ?string $boundary = null)
    {
        $this->boundary = $boundary ?: \sha1(\uniqid('', true));
        $this->stream = $this->createStream($elements);
    }

    public function getBoundary(): ?string
    {
        return $this->boundary;
    }

    public function isWritable(): bool
    {
        return false;
    }

    /**
     * Get the headers needed before transferring the content of a POST file
     *
     * @param dict<string, string> $headers
     * @return string
     */
    private function getHeaders(dict<arraykey, mixed> $headers): string
    {
        $str = '';
        foreach ($headers as $key => $value) {
            if($key is string && $value is string) {
                $str .= "{$key}: {$value}\r\n";
            }
        }

        return "--{$this->boundary}\r\n" . \trim($str) . "\r\n\r\n";
    }

    /**
     * Create the aggregate stream that will be used to upload the POST data
     */
    protected function createStream(vec<dict<string, mixed>> $elements = vec[]): StreamInterface
    {
        $stream = new AppendStream();

        foreach ($elements as $element) {
            $this->addElement($stream, $element);
        }

        // Add the trailing boundary with CRLF
        $stream->addStream(Utils::streamFor("--{$this->boundary}--\r\n"));

        return $stream;
    }

    private function addElement(AppendStream $stream, dict<string, mixed> $element): void
    {
        foreach (vec['contents', 'name'] as $key) {
            if (!\array_key_exists($key, $element)) {
                throw new \InvalidArgumentException("A '{$key}' key is required");
            }
        }

        $element['contents'] = Utils::streamFor($element['contents']);

        if (!\isset($element['filename'])) {
            $element_contents = $element['contents'];

            if($element_contents is StreamInterface) {
                $uri = $element_contents->getMetadata('uri');
                if ($uri is string) {
                    $element['filename'] = $uri;
                }
            }
        }

        $element_name = HH\idx($element, 'name');
        $element_contents = HH\idx($element, 'contents');
        $element_filename = HH\idx($element, 'filename'); 
        $element_headers = HH\idx($element, 'headers'); 

        if($element_name is string && $element_contents is StreamInterface  ) {

            $element_filename = $element_filename is string ? $element_filename: null;
            $element_headers = $element_headers is dict<_,_> ? $element_headers: dict[];

            $body_headers = $this->createElement($element_name,$element_contents,$element_filename,$element_headers);

            $_body = $body_headers[0];
            $_headers = $body_headers[1];

            $stream->addStream(Utils::streamFor($this->getHeaders($_headers)));
            $stream->addStream($_body);
            $stream->addStream(Utils::streamFor("\r\n"));
        }
        
    }

    private function createElement(string $name, 
        StreamInterface $stream, 
        ?string $filename, 
        dict<arraykey, mixed> $headers): (StreamInterface, dict<arraykey, mixed>)
    {
        // Set a default content-disposition header if one was no provided
        $disposition = $this->getHeader($headers, 'content-disposition');
        if (!$disposition) {
            if($filename is string) {
                $headers['Content-Disposition'] = 
                    \sprintf('form-data; name="%s"; filename="%s"',$name,\basename($filename));
            } else {
                $headers['Content-Disposition'] = "form-data; name=\"{$name}\"";
            }
        }

        // Set a default content-length header if one was no provided
        $length = $this->getHeader($headers, 'content-length');
        if (!$length) {
            $length = $stream->getSize();
            if ($length) {
                $headers['Content-Length'] = (string) $length;
            }
        }

        // Set a default Content-Type if one was not supplied
        $type = $this->getHeader($headers, 'content-type');
        if (!$type && $filename is string) {
            $type = MimeType::fromFilename($filename);
            if ($type) {
                $headers['Content-Type'] = $type;
            }
        }

        return tuple($stream, $headers);
    }

    private function getHeader(dict<arraykey, mixed> $headers, string $key): ?string
    {
        $lowercaseHeader = \strtolower($key);
        foreach ($headers as $k => $v) {
            if ($k is string && $v is string && \strtolower($k) === $lowercaseHeader) {
                return $v;
            }
        }

        return null;
    }
}

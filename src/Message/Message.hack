namespace HackHttp\Message;

use namespace HH;
use namespace HH\Lib\Vec;
use namespace HH\Lib\Dict;
use namespace HH\Lib\Str;

final class Message
{
    /**
     * Returns the string representation of an HTTP message.
     *
     * @param MessageInterface $message Message to convert to a string.
     */
    public static function toString(MessageInterface $message): string
    {
        if ($message is RequestInterface) {
            $msg = \trim($message->getMethod() . ' '
                    . $message->getRequestTarget())
                . ' HTTP/' . $message->getProtocolVersion();
            if (!$message->hasHeader('host')) {
                $msg .= "\r\nHost: " . $message->getUri()->getHost();
            }
        } elseif ($message is ResponseInterface) {
            $msg = 'HTTP/' . $message->getProtocolVersion() . ' '
                . $message->getStatusCode() . ' '
                . $message->getReasonPhrase();
        } else {
            throw new \InvalidArgumentException('Unknown message type');
        }

        foreach ($message->getHeaders() as $name => $values) {
            if (\strtolower($name) === 'set-cookie') {
                foreach ($values as $value) {
                    $msg .= "\r\n{$name}: " . $value;
                }
            } else {
                $msg .= "\r\n{$name}: " . \implode(', ', $values);
            }
        }

        $body = $message->getBody();

        if($body is StreamInterface) {
            return "{$msg}\r\n\r\n" . $body->__toString();
        } elseif($body is string) {
            return "{$msg}\r\n\r\n" . $body;
        } else {
            return "{$msg}\r\n\r\n";
        }

    }

    /**
     * Get a short summary of the message body.
     *
     * Will return `null` if the response is not printable.
     *
     * @param MessageInterface $message    The message to get the body summary
     * @param int              $truncateAt The maximum allowed size of the summary
     */
    public static function bodySummary(MessageInterface $message, int $truncateAt = 120): ?string
    {
        $body = $message->getBody();

        if (!$body->isSeekable() || !$body->isReadable()) {
            return null;
        }

        $size = $body->getSize();

        if ($size === 0) {
            return null;
        }

        $summary = $body->read($truncateAt);
        $body->rewind();

        if ($size is int && $size > $truncateAt) {
            $summary .= ' (truncated...)';
        }

        // Matches any printable character, including unicode characters:
        // letters, marks, numbers, punctuation, spacing, and separators.
        if (\preg_match('/[^\pL\pM\pN\pP\pS\pZ\n\r\t]/u', $summary)) {
            return null;
        }

        return $summary;
    }

    /**
     * Attempts to rewind a message body and throws an exception on failure.
     *
     * The body of the message will only be rewound if a call to `tell()`
     * returns a value other than `0`.
     *
     * @param MessageInterface $message Message to rewind
     *
     * @throws \RuntimeException
     */
    public static function rewindBody(MessageInterface $message): void
    {
        $body = $message->getBody();

        if ($body->tell()) {
            $body->rewind();
        }
    }

    /**
     * Parses an HTTP message into a dictionary.
     *
     * The dictionary contains the "start-line" key containing the start line of
     * the message, "headers" key containing a dict of header
     * vec<string> values, and a "body" key containing the body of the message.
     *
     * @param string $message HTTP request or response to parse.
     */
    public static function parseMessage(string $message): dict<string, mixed>
    {
        if (!$message) {
            throw new \InvalidArgumentException('Invalid message');
        }

        $message = \ltrim($message, "\r\n");

        $messageParts = \preg_split("/\r?\n\r?\n/", $message, 2);

        if ($messageParts === false || \count($messageParts) !== 2) {
            throw new \InvalidArgumentException('Invalid message: Missing header delimiter');
        }

        $rawHeaders = $messageParts[0];
        $body = $messageParts[1];

        $rawHeaders .= "\r\n"; // Put back the delimiter we split previously
        $headerParts = \preg_split("/\r?\n/", $rawHeaders, 2);

        if ($headerParts === false || \count($headerParts) !== 2) {
            throw new \InvalidArgumentException('Invalid message: Missing status line');
        }

        $startLine = $headerParts[0];
        $rawHeaders = $headerParts[1];
       
        $matches = vec<string>[];
        if (\preg_match_with_matches("/(?:^HackHttp\/|^[A-Z]+ \S+ HackHttp\/)(\d+(?:\.\d+)?)/i", $startLine, inout $matches) && $matches[1] === '1.0') {
            // Header folding is deprecated for HTTP/1.1, but allowed in HTTP/1.0
            $rawHeaders = \preg_replace(Rfc7230::HEADER_FOLD_REGEX, ' ', $rawHeaders);
        }

        $headerLines=vec[];
        $count = \preg_match_all_with_matches(Rfc7230::HEADER_REGEX, $rawHeaders, inout $headerLines, \PREG_SET_ORDER);

        // If these aren't the same, then one line didn't match and there's an invalid header.
        if ($count !== \substr_count($rawHeaders, "\n")) {
            // Folding is deprecated, see https://tools.ietf.org/html/rfc7230#section-3.2.4
            if (\preg_match(Rfc7230::HEADER_FOLD_REGEX, $rawHeaders)) {
                throw new \InvalidArgumentException('Invalid header syntax: Obsolete line folding');
            }

            throw new \InvalidArgumentException('Invalid header syntax');
        }

        $headers = dict[];

        foreach ($headerLines as $headerLine) {
            $headers[$headerLine[1]][] = $headerLine[2];
        }

        return dict[
            'start-line' => $startLine,
            'headers' => $headers,
            'body' => $body,
        ];
    }

    /**
     * Constructs a URI for an HTTP request message.
     *
     * @param string $path    Path from the start-line
     * @param dict<arraykey, mixed>  $headers dict of headers (each value is vec<string>).
     */
    public static function parseRequestUri(string $path, dict<arraykey, mixed> $headers): string
    {
        $header_keys = Vec\keys($headers);

        $host_cb = (arraykey $k): bool ==> ($k is string) && (\strtolower($k) === 'host');
        $hostKey = Vec\filter($header_keys, $host_cb);

        // If no host is found, then a full URI cannot be constructed.
        if (!$hostKey) {
            return $path;
        }

        $host_values = HH\idx($headers, $hostKey[0]);
        if($host_values is vec<_>) {
            $host = $host_values[0];
            if($host is string) {
                $scheme = Str\slice($host, -4) === ':443' ? 'https' : 'http';
                return $scheme . '://' . $host . '/' . \ltrim($path, '/');
            }
        }

        return $path;
    }

    /**
     * Parses a request message string into a request object.
     *
     * @param string $message Request message string.
     */
    public static function parseRequest(string $message): RequestInterface
    {
        $data = self::parseMessage($message);
        $matches = vec[];

        $start_line = HH\idx($data, 'start-line');

        if($start_line is string) {
            if (!\preg_match_with_matches('/^[\S]+\s+([a-zA-Z]+:\/\/|\/).*/', $start_line, inout $matches)) {
                throw new \InvalidArgumentException('Invalid request string');
            }
       
            $parts = \explode(' ', $start_line, 3);
            $version = \isset($parts[2]) ? \explode('/', $parts[2])[1] : '1.1';
            $headers = HH\idx($data, 'headers');
            
            if($headers is dict<_,_>) {
                $body = HH\idx($data, 'body');

                $request = new Request(
                    $parts[0],
                    $matches[1] === '/' ? self::parseRequestUri($parts[1], $headers) : $parts[1],
                    Utils::filterHeaders($headers),
                    $body,
                    $version
                );

                return $matches[1] === '/' ? $request : $request->withRequestTarget($parts[1]);
            } else {
                 throw new \RuntimeException("Headers must be dict<string, vec<string>>");
            }
        } else {
            throw new \RuntimeException("start-line is not a string");
        }
    }

    /**
     * Parses a response message string into a response object.
     *
     * @param string $message Response message string.
     */
    public static function parseResponse(string $message): ResponseInterface
    {
        $data = self::parseMessage($message);

        $start_line = HH\idx($data, 'start-line');

        if($start_line is string) {

            if (!\preg_match('/^HackHttp\/.* [0-9]{3}( .*|$)/', $start_line)) {
                throw new \InvalidArgumentException('Invalid response string: ' . $start_line);
            }

            $parts = \explode(' ', $start_line, 3);
            $headers = HH\idx($data, 'headers');
            if($headers is dict<_,_>) {
                $body = HH\idx($data, 'body');
                return new Response(
                    (int) $parts[1],
                    Utils::filterHeaders($headers),
                    $body,
                    \explode('/', $parts[0])[1],
                    $parts[2] ?? null
                );
            } else {
                throw new \RuntimeException("Headers must be dict<string, vec<string>>");
            }
        } else {
            throw new \RuntimeException("start-line is not a string");
        }
    }
}

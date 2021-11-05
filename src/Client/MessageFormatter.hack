namespace HackHttp\Client;

use HH\Lib\Str;

use HackHttp\Message\MessageInterface;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\Message;

/**
 * Formats log messages using variable substitutions for requests, responses,
 * and other transactional data.
 *
 * The following variable substitutions are supported:
 *
 * - {request}:        Full HTTP request message
 * - {response}:       Full HTTP response message
 * - {ts}:             ISO 8601 date in GMT
 * - {date_iso_8601}   ISO 8601 date in GMT
 * - {date_common_log} Apache common log date using the configured timezone.
 * - {host}:           Host of the request
 * - {method}:         Method of the request
 * - {uri}:            URI of the request
 * - {version}:        Protocol version
 * - {target}:         Request target of the request (path + query + fragment)
 * - {hostname}:       Hostname of the machine that sent the request
 * - {code}:           Status code of the response (if available)
 * - {phrase}:         Reason phrase of the response  (if available)
 * - {error}:          Any error messages (if available)
 * - {req_header_*}:   Replace `*` with the lowercased name of a request header to add to the message
 * - {res_header_*}:   Replace `*` with the lowercased name of a response header to add to the message
 * - {req_headers}:    Request headers
 * - {res_headers}:    Response headers
 * - {req_body}:       Request body
 * - {res_body}:       Response body
 *
 */
final class MessageFormatter implements MessageFormatterInterface
{
    /**
     * Apache Common Log Format.
     *
     * @link https://httpd.apache.org/docs/2.4/logs.html#common
     *
     * @var string
     */
    const string CLF = "{hostname} {req_header_User-Agent} - [{date_common_log}] \"{method} {target} HTTP/{version}\" {code} {res_header_Content-Length}";
    const string DEBUG = ">>>>>>>>\n{request}\n<<<<<<<<\n{response}\n--------\n{error}";
    const string SHORT = '[{ts}] "{method} {target} HTTP/{version}" {code}';

    /**
     * @var string Template used to format log messages
     */
    private string $template;

    private dict<string, string> $cache = dict[];

    /**
     * @param string $template Log message template
     */
    public function __construct(?string $template = self::CLF)
    {
        $this->template = $template ?: self::CLF;
    }

    /**
     * Returns a formatted message string.
     *
     * @param RequestInterface       $request  Request that was sent
     * @param ?ResponseInterface $response Response that was received
     *
     * @return string formatted message
     * @param  mixed        $error    Exception that was received
     */
    public function format(RequestInterface $request, 
                        ?ResponseInterface $response = null, 
                         mixed $error = null): string
    {
    
        $cb = (vec<string> $matches) : string ==> {
            if (isset($this->cache[$matches[1]])) {
                return $this->cache[$matches[1]];
            }

            $result = '';
            switch ($matches[1]) {
                case 'request':
                    $result = Message::toString($request);
                    break;
                case 'response':
                    $result = $response ? Message::toString($response) : '';
                    break;
                case 'req_headers':
                    $result = \trim($request->getMethod()
                                . ' ' . $request->getRequestTarget())
                            . ' HTTP/' . $request->getProtocolVersion() . "\r\n"
                            . $this->headers($request);
                    break;
                case 'res_headers':
                    $result = $response ?
                            \sprintf(
                                'HTTP/%s %d %s',
                                $response->getProtocolVersion(),
                                $response->getStatusCode(),
                                $response->getReasonPhrase()
                            ) . "\r\n" . $this->headers($response)
                            : 'NULL';
                    break;
                case 'req_body':
                    $result = $request->getBody()->__toString();
                    break;
                case 'res_body':
                    if (!($response is ResponseInterface)) {
                        $result = 'NULL';
                        break;
                    }

                    $body = $response->getBody();

                    if (!$body->isSeekable()) {
                        $result = 'RESPONSE_NOT_LOGGEABLE';
                        break;
                    }

                    $result = $response->getBody()->__toString();
                    break;
                case 'ts':
                case 'date_iso_8601':
                    $result = (string)\gmdate('c');
                    break;
                case 'date_common_log':
                    $result = (string)\date('d/M/Y:H:i:s O');
                    break;
                case 'method':
                    $result = $request->getMethod();
                    break;
                case RequestOptions::VERSION:
                    $result = $request->getProtocolVersion();
                    break;
                case 'uri':
                case 'url':
                    $result = $request->getUri()->__toString();
                    break;
                case 'target':
                    $result = $request->getRequestTarget();
                    break;
                case 'req_version':
                    $result = $request->getProtocolVersion();
                    break;
                case 'res_version':
                    $result = $response ? $response->getProtocolVersion() : 'NULL';
                    break;
                case 'host':
                    $result = $request->getHeaderLine('Host');
                    break;
                case 'hostname':
                    $hostname = \gethostname();
                    if ($hostname is string) {
                        $result = $hostname;
                    } else {
                        $result = 'NULL';
                    }

                    break;
                case 'code':
                    $result = $response ? (string)$response->getStatusCode() : 'NULL';
                    break;
                case 'phrase':
                    $result = $response ? $response->getReasonPhrase() : 'NULL';
                    break;
                case 'error':
                    $result = $error is \Exception ? $error->getMessage() : 'NULL';
                    break;
                default:
                    // handle prefixed dynamic headers
                    if (Str\search($matches[1], 'req_header_') === 0) {
                        $result = $request->getHeaderLine(Str\slice($matches[1], 11));
                    } elseif (Str\search($matches[1], 'res_header_') === 0) {
                        $result = $response ? $response->getHeaderLine(Str\slice($matches[1], 11)) : 'NULL';
                    }
                }

            $this->cache[$matches[1]] = $result;
            return $result;
        };

        $count = 0;
        return \preg_replace_callback(
            '/{\s*([A-Za-z_\-\.0-9]+)\s*}/',
            $cb,
            $this->template,
            -1, inout $count);
    }

    /**
     * Get headers from message as string
     */
    private function headers(MessageInterface $message): string
    {
        $result = '';
        foreach ($message->getHeaders() as $name => $values) {
            $result .= $name . ': ' . \implode(', ', $values) . "\r\n";
        }

        return \trim($result);
    }
}

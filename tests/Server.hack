namespace HackHttp\Tests;

use namespace HackHttp\Client as HC;
use namespace HackHttp\Message as HM;

use HackHttp\Client\RequestOptions;

use namespace HH;

/**
 * The Server class is used to control a scripted webserver using node.js that
 * will respond to HTTP requests with queued responses.
 *
 * Queued responses will be served to requests using a FIFO order.  All requests
 * received by the server are stored on the node.js server and can be retrieved
 * by calling {@see Server::received()}.
 *
 * Mock responses that don't require data to be transmitted over HTTP a great
 * for testing.  Mock response, however, cannot test the actual sending of an
 * HTTP request using cURL.  This test server allows the simulation of any
 * number of HTTP request response transactions to test the actual sending of
 * requests over the wire without having to leave an internal network.
 */
class Server
{
    /**
     * @var Client
     */
    private static ?HC\Client $client;
    private static bool $started = false;
    public static string $url = 'http://127.0.0.1:8126/';
    public static int $port = 8126;

    /**
     * Flush the received requests from the server
     *
     * @throws \RuntimeException
     */
    public static function flush(): HM\ResponseInterface
    {
        return self::getClient()->request('DELETE', 'hack-http-server/requests');
    }

    /**
     * Queue an array of responses or a single response on the server.
     *
     * Any currently queued responses will be overwritten.  Subsequent requests
     * on the server will return queued responses in FIFO order.
     *
     * @param vec<HM\ResponseInterface> $responses A single or array of Responses
     *                                           to queue.
     *
     * @throws \Exception
     */
    public static function enqueue(vec<HM\ResponseInterface> $responses): void
    {
        $data = vec[];
        foreach ($responses as $response) {
            if (!($response is HM\ResponseInterface)) {
                throw new \RuntimeException('Invalid response given.');
            }
            $headers = \array_map( ($h) ==> {
                return \implode(' ,', $h);
            }, $response->getHeaders());

            $data[] = dict [
                'status'  => (string) $response->getStatusCode(),
                'reason'  => $response->getReasonPhrase(),
                RequestOptions::HEADERS => $headers,
                RequestOptions::BODY    => \base64_encode($response->getBody()->__toString())
            ];
        }

        self::getClient()->request('PUT', 'hack-http-server/responses', dict[RequestOptions::JSON => $data]);
    }

    /**
     * Queue a single raw response manually.
     *
     * @param int|string  $statusCode   Status code for the response, e.g. 200
     * @param string      $reasonPhrase Status reason response e.g "OK"
     * @param array       $headers      Array of headers to send in response
     * @param string|null $body         Body to send in response
     *
     */
    public static function enqueueRaw(arraykey $statusCode, string $reasonPhrase, dict<arraykey, mixed> $headers, mixed $body): void
    {
        $data = vec[
            dict[
                'status'  => (string) $statusCode,
                'reason'  => $reasonPhrase,
                RequestOptions::HEADERS => $headers,
                RequestOptions::BODY    => \base64_encode((string) $body)
            ]
        ];

        self::getClient()->request('PUT', 'hack-http-server/responses', dict[RequestOptions::JSON => $data]);
    }

    /**
     * Get all of the received requests
     *
     * @return vec<HM\RequestInterface>
     *
     * @throws \RuntimeException
     */
    public static function received(): vec<HM\RequestInterface>
    {
        if (!self::$started) {
            return vec[];
        }

        $response = self::getClient()->request('GET', 'hack-http-server/requests');
        $data = \json_decode($response->getBody()->__toString(), true);

        return vec(\array_map(
            (dict<arraykey, mixed> $message): HM\RequestInterface ==> {
                $uri = HH\idx($message,'uri');
                $query_string = HH\idx($message,'query_string');
                $http_method = HH\idx($message,'http_method');
                $headers = HH\idx($message,RequestOptions::HEADERS);
                $body = HH\idx($message,RequestOptions::BODY);
                $version = HH\idx($message,RequestOptions::VERSION);

                if ($uri is string && 
                    $query_string is ?string &&
                    $http_method is string &&
                    $headers is dict<_,_> &&
                    $version is string) {
                        
                        if($query_string) {
                            $uri .= '?' . $query_string;
                        }
                        $headers = HM\Utils::filterHeaders($headers);

                        return new HM\Request(
                            $http_method,
                            $uri,
                            $headers,
                            $body,
                            $version
                        );
                }

                throw new \RuntimeException("invalid request in response from hack-http-server");
               
            },
            $data
        ));
    }

    /**
     * Stop running the node.js server
     */
    public static function stop(): void
    {
        if (self::$started) {
            self::getClient()->request('DELETE', 'hack-http-server');
        }

        self::$started = false;
    }

    public static function wait(int $maxTries = 10): void
    {
        $tries = 0;
        while (!self::isListening() && ($tries < $maxTries) ) {
            \usleep(1000000);
            $tries++;
        }

        if (!($tries < $maxTries)) {
            throw new \RuntimeException("Unable to contact node.js server after {$tries} tries");
        }
    }

    public static function start(): void
    {
        if (self::$started) {
            return;
        }

        if (!self::isListening()) {
            $tmp_dir = \sys_get_temp_dir();
            $cmd = 'node ' . __DIR__ . '/server.js '
                . self::$port . ' >> ' . $tmp_dir . 'hack-http-server.log 2>&1 &';
            \shell_exec($cmd);
            self::wait();

            \register_shutdown_function(() ==> {
                self::stop();
            });
        }

        self::$started = true;
    }

    private static function isListening(): bool
    {
        try {
            self::getClient()->request('GET', 'hack-http-server/perf', dict[
                RequestOptions::CONNECT_TIMEOUT => 5,
                RequestOptions::TIMEOUT         => 5
            ]);
            return true;
        } catch (\Throwable $e) {
            return false;
        }
    }

    private static function getClient(): HC\Client
    {
        if (!self::$client) {
            self::$client = new HC\Client(dict[
                'base_uri' => self::$url,
                'sync'     => true,
            ]);
        }

        return self::$client;
    }
}

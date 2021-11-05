namespace HackHttp\Tests\Client\Handler;

use HackHttp\Tests\Helper;
use HackHttp\Tests\Server;

use HackHttp\Client\Exception\ConnectException;
use HackHttp\Client\Exception\RequestException;
use HackHttp\Client\Handler\CurlFactory;
use HackHttp\Client\Handler\EasyHandle;
use HackHttp\Client\RequestOptions;
use namespace HackPromises as P;
use namespace HackHttp\Message as HM;
use namespace HackHttp\Client\Handler as HCH;
use namespace HackHttp\Client\Exception as HCE;

use HackHttp\Client\TransferStats;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\HackTest;
use HackHttp\HM\ResponseInterface;

/**
 * @covers HackHttp\Client\HCH\CurlFactory
 */
class CurlFactoryTest extends HackTest
{

    <<__Override>>
    public static async function beforeFirstTestAsync(): Awaitable<void> 
    {
        Server::start();
    }

    <<__Override>>
    public static async function afterLastTestAsync(): Awaitable<void> 
    {
        Server::stop();
    }

    public function testCreatesCurlHandle(): void
    {
        Server::flush();
        Server::enqueue(vec[
            new HM\Response(200, dict[
                'Foo' => vec['Bar'],
                'Baz' => vec['bam'],
                'Content-Length' => vec['2'],
            ], 'hi')
        ]);
        $stream = HM\Utils::streamFor(null);
        $request = new HM\Request('PUT', Server::$url, dict[
            'Hi'             => vec[' 123'],
            'Content-Length' => vec['7']
        ], 'testing');
        $f = new HCH\CurlFactory();
        $result = $f->create($request, dict[RequestOptions::SINK => $stream]);
        Helper::assertInstanceOf(EasyHandle::class, $result);
        expect($result->getHandle())->toBeType('resource');
        Helper::assertIsArray($result->getHeaders());
        Helper::assertIsArray($result->getOptions());
        Helper::assertSame($stream, $result->getOption(RequestOptions::SINK));
        Helper::assertSame($stream, $result->getSink());
        $f->release($result);
    }

    public function testValidatesVerify(): void
    {
        $f = new HCH\CurlFactory();

        expect(() ==> $f->create(new HM\Request('GET', Server::$url), 
            dict[RequestOptions::VERIFY => '/does/not/exist']))->toThrow(\InvalidArgumentException::class, 
                'SSL CA bundle not found: /does/not/exist');
    }

    public function testCanSetVerifyToFile(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', 'http://foo.com'), dict[RequestOptions::VERIFY => __FILE__]);
        $f->release($result);
    }

    public function testCanSetVerifyToDir(): void
    {
        $f = new HCH\CurlFactory();
        $result =  $f->create(new HM\Request('GET', 'http://foo.com'), dict[RequestOptions::VERIFY => __DIR__]);
        $f->release($result);
    }

    public function testAddsVerifyAsTrue(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', Server::$url), dict[RequestOptions::VERIFY => true]);
        $f->release($result);
    }

    public function testCanDisableVerify(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', Server::$url), dict[RequestOptions::VERIFY => false]);
        $f->release($result);
    }

    public function testAddsProxy(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', Server::$url), dict[RequestOptions::PROXY => 'http://bar.com']);
        $f->release($result);
    }
    
    public function testAddsViaScheme(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', Server::$url), dict[
            RequestOptions::PROXY => dict['http' => 'http://bar.com', 'https' => 'https://t'],
        ]);
        $f->release($result);

        $this->checkNoProxyForHost('http://test.test.com', vec['test.test.com'], false);
        $this->checkNoProxyForHost('http://test.test.com', vec['.test.com'], false);
        $this->checkNoProxyForHost('http://test.test.com', vec['*.test.com'], true);
        $this->checkNoProxyForHost('http://test.test.com', vec['*'], false);
        $this->checkNoProxyForHost('http://127.0.0.1', vec['127.0.0.*'], true);
    }

    
    private function checkNoProxyForHost(string $url, vec<string> $noProxy, bool $assertUseProxy): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', $url), dict[
            RequestOptions::PROXY => dict[
                'http' => 'http://bar.com',
                'https' => 'https://t',
                'no' => $noProxy
            ],
        ]);
        $f->release($result);
    }


    public function testValidatesSslKey(): void
    {
        $f = new HCH\CurlFactory();

        expect(() ==> $f->create(new HM\Request('GET', Server::$url), 
            dict[RequestOptions::SSL_KEY => '/does/not/exist']))->toThrow(\InvalidArgumentException::class, 
            'SSL private key file not found: /does/not/exist');
    }

    public function testAddsSslKey(): void
    {
        $f = new HCH\CurlFactory();
        $result =  $f->create(new HM\Request('GET', Server::$url), dict[RequestOptions::SSL_KEY => __FILE__]);
        $f->release($result);
    }

    public function testAddsSslKeyWithPassword(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', Server::$url), dict[RequestOptions::SSL_KEY => vec[__FILE__, 'test']]);
        $f->release($result);
    }

    public function testAddsSslKeyWhenUsingArraySyntaxButNoPassword(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', Server::$url), dict[RequestOptions::SSL_KEY => vec[__FILE__]]);
        $f->release($result);
    }

    public function testValidatesCert(): void
    {
        $f = new HCH\CurlFactory();
        expect(() ==> $f->create(new HM\Request('GET', Server::$url),  dict[RequestOptions::CERT => '/does/not/exist']))->toThrow(\InvalidArgumentException::class, 
                'SSL certificate file not found: /does/not/exist');
    }

    public function testAddsCert(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', Server::$url),  dict[RequestOptions::CERT => __FILE__]);
        $f->release($result);
    }

    public function testAddsCertWithPassword(): void
    {
        $f = new HCH\CurlFactory();
        $result =  $f->create(new HM\Request('GET', Server::$url),  dict[RequestOptions::CERT => vec[__FILE__, 'test']]);
        $f->release($result);
    }

    public function testAddsDerCert(): void
    {
        $certFile = \tempnam(\sys_get_temp_dir(), "mock_test_cert");
        $certFileDer = $certFile. '.der';
        \rename($certFile, $certFileDer);
        try {
            $f = new HCH\CurlFactory();
            $result = $f->create(new HM\Request('GET', Server::$url),  dict[RequestOptions::CERT => $certFileDer]);
            $f->release($result);
        } finally {
            \unlink($certFileDer);
        }
    }

    public function testAddsP12Cert(): void
    {
        $certFile = \tempnam(\sys_get_temp_dir(), "mock_test_cert");
        $certFileP12 = $certFile. '.p12';
        \rename($certFile, $certFileP12);
        try {
            $f = new HCH\CurlFactory();
            $result = $f->create(new HM\Request('GET', Server::$url),  dict[RequestOptions::CERT => $certFileP12]);
            $f->release($result);
        } finally {
            \unlink($certFileP12);
        }
    }

    public function testValidatesProgress(): void
    {
        $f = new HCH\CurlFactory();

        expect(() ==> $f->create(new HM\Request('GET', Server::$url), 
            dict[RequestOptions::PROGRESS => 'foo']))->toThrow(\InvalidArgumentException::class, 
                'progress client option must be a ProgressCallbackInterface');
    }

    public function testValidatesOnStats(): void
    {
        $f = new HCH\CurlFactory();

        expect(() ==> $f->create(new HM\Request('GET', Server::$url), 
            dict[RequestOptions::ON_STATS => 'foo']))->toThrow(\InvalidArgumentException::class, 
                'on_stats client option must be a TransferStatsCallbackInterface');
    }

    public function testAddsTimeouts(): void
    {
        $f = new HCH\CurlFactory();
        $result = $f->create(new HM\Request('GET', Server::$url), dict[
            RequestOptions::TIMEOUT         => 0.1,
            RequestOptions::CONNECT_TIMEOUT => 0.2
        ]);
        $f->release($result);
    }

    public function testEnsuresDirExistsBeforeThrowingWarning(): void
    {
        $f = new HCH\CurlFactory();

        expect(() ==> $f->create(new HM\Request('GET', Server::$url), dict[
            RequestOptions::SINK => '/does/not/exist/so/error.txt'
        ]))->toThrow(\RuntimeException::class, 
        'Directory /does/not/exist/so does not exist for sink value of /does/not/exist/so/error.txt');
    }

    public function testRejectsPromiseWhenCreateResponseFails(): void
    {
        Server::flush();
        Server::enqueueRaw(999, "Incorrect", dict['X-Foo' => 'bar'], 'abc 123');

        $req = new HM\Request('GET', Server::$url);
        $handler = new HCH\CurlHandler();
        $promise = $handler->handle($req, dict[]);

        expect(() ==> $promise->wait())->toThrow(HCE\RequestException::class, 'An error was encountered while creating the response');
    }

    public function testEnsuresOnHeadersIsCallable(): void
    {
        $req = new HM\Request('GET', Server::$url);
        $handler = new HCH\CurlHandler();

        expect(() ==> $handler->handle($req, dict[RequestOptions::ON_HEADERS => 'error!']))->toThrow(\InvalidArgumentException::class);
    }

    public function testRejectsPromiseWhenOnHeadersFails(): void
    {
        Server::flush();
        Server::enqueue(vec[
            new HM\Response(200, dict['X-Foo' => vec['bar']], 'abc 123')
        ]);
        $req = new HM\Request('GET', Server::$url);
        $handler = new HCH\CurlHandler();
        $promise = $handler->handle($req, dict[
            RequestOptions::ON_HEADERS => (new OnHeaderFails())
        ]);

        expect(() ==> $promise->wait())->toThrow(RequestException::class, 'An error was encountered during the on_headers event');
    }

    public function testSuccessfullyCallsOnHeadersBeforeWritingToSink(): void
    {
        Server::flush();
        Server::enqueue(vec[
            new HM\Response(200, dict['X-Foo' => vec['bar']], 'abc 123')
        ]);
        $req = new HM\Request('GET', Server::$url);

        $stream = HM\Utils::streamFor(null);

        $handler = new HCH\CurlHandler();
        $promise = $handler->handle($req, dict[
            RequestOptions::SINK       => $stream,
            RequestOptions::ON_HEADERS => (new OnHeaderSucceeds('bar'))
        ]);

        $response = $promise->wait();
        expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
        if($response is HM\ResponseInterface) {
            Helper::assertSame(200, $response->getStatusCode());
            Helper::assertSame('bar', $response->getHeaderLine('X-Foo'));
            Helper::assertSame('abc 123',  $response->getBody()->__toString());
        }
    }

    public function testInvokesOnStatsOnSuccess(): void
    {
        Server::flush();
        Server::enqueue(vec[new HM\Response(200)]);
        $req = new HM\Request('GET', Server::$url);
      
        $handler = new HCH\CurlHandler();
        $on_stats = new OnStatsTestCallback();
        $promise = $handler->handle($req, dict[RequestOptions::ON_STATS => $on_stats]);
        $response = $promise->wait();
        expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
        if($response is HM\ResponseInterface) {
            $gotStats = $on_stats->getStats();
            expect($gotStats)->toNotBeNull();

            if($gotStats is nonnull) {
                Helper::assertSame(200, $response->getStatusCode());
                $stats_response = $gotStats->getResponse();
                expect($stats_response)->toNotBeNull();
                if($stats_response is nonnull) {
                    Helper::assertSame(200, $stats_response->getStatusCode());
                }
                Helper::assertSame(Server::$url, $gotStats->getEffectiveUri()->__toString());
                Helper::assertSame(Server::$url,$gotStats->getRequest()->getUri()->__toString());
                $tt = $gotStats->getTransferTime();
                if($tt is nonnull) {
                    Helper::assertGreaterThan(0, $tt);
                }
                Helper::assertArrayHasKey('appconnect_time', $gotStats->getHandlerStats());
            }
        }
    }

    public function testRewindsBodyIfPossible(): void
    {
        $body = HM\Utils::streamFor(\str_repeat('x', 1024 * 1024 * 2));
        $body->seek(1024 * 1024);
        Helper::assertSame(1024 * 1024, $body->tell());

        $req = new HM\Request('POST', 'https://www.example.com', dict[
            'Content-Length' => vec[(string)(1024 * 1024 * 2)]], $body);
        $factory = new CurlFactory();
        $result = $factory->create($req, dict[]);
        Helper::assertSame(0, $body->tell());
        $factory->release($result);
    }

    public function testDoesNotRewindUnseekableBody(): void
    {
        $body = HM\Utils::streamFor(\str_repeat('x', 1024 * 1024 * 2));
        $body->seek(1024 * 1024);
        $body = new HM\NoSeekStream($body);
        Helper::assertSame(1024 * 1024, $body->tell());

        $req = new HM\Request('POST', 'https://www.example.com', dict[
            'Content-Length' => vec[(string)(1024 * 1024)]], $body);
        $factory = new CurlFactory();
        $factory->create($req, dict[]);

        Helper::assertSame(1024 * 1024, $body->tell());
    }
}

namespace HackHttp\Tests\Client\Handler;

use HackHttp\Tests\Helper;
use HackHttp\Tests\Server;

use namespace HackPromises as P;
use namespace HackHttp\Message as HM;
use namespace HackHttp\Client\Handler as HCH;
use namespace HackHttp\Client as HC;

use function Facebook\FBExpect\expect;
use type Facebook\HackTest\HackTest;
use HackHttp\Client\RequestOptions;

use namespace HH\Lib\OS;

class CurlMultiHandlerTest extends HackTest
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

    public function testSendsHeadRequests(): void
    {
        Server::flush();
        Server::enqueue(vec[new HM\Response()]);
        $a = new HCH\CurlMultiHandler();
            $response = $a->handle(new HM\Request('HEAD', Server::$url), dict[]);
            $response->wait();
            Helper::assertEquals('HEAD', Server::received()[0]->getMethod());
        
    }

    
    public function testCanAddCustomCurlOptions(): void
    {
        Server::flush();
        Server::enqueue(vec[new HM\Response()]);
        $a = new HCH\CurlMultiHandler();
            $req = new HM\Request('GET', Server::$url);
            $a->handle($req, dict['curl' => dict[\CURLOPT_LOW_SPEED_LIMIT => 10]]);
        
    }

    public function testUsesProxy(): void
    {
        Server::flush();
        Server::enqueue(vec[
            new HM\Response(200, dict[
                'Foo' => vec['Bar'],
                'Baz' => vec['bam'],
                'Content-Length' => vec['2'],
            ], 'hi')
        ]);

       $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('GET', 'http://www.example.com', dict[], null, '1.0');
            $promise = $handler->handle($request, dict[
                RequestOptions::PROXY => Server::$url
            ]);
            $response = $promise->wait();
            expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
            if($response is HM\ResponseInterface) {
                Helper::assertSame(200, $response->getStatusCode());
                Helper::assertSame('Bar', $response->getHeaderLine('Foo'));
                Helper::assertSame('2', $response->getHeaderLine('Content-Length'));
                Helper::assertSame('hi', $response->getBody()->__toString());
            }
    }

    public function testEmitsDebugInfoToStream(): void
    {
        $tmp_dir = \sys_get_temp_dir();
        $path = OS\mkstemp("{$tmp_dir}/hack-http-XXXXXX")[1];
        $res = \fopen($path, 'r+');
        Server::flush();
        Server::enqueue(vec[new HM\Response()]);
        $a = new HCH\CurlMultiHandler();
            $promise = $a->handle(new HM\Request('HEAD', Server::$url), dict['debug' => $res]);
            $promise->wait();
            \rewind($res);
            $output = \str_replace("\r", '', \stream_get_contents($res));
            Helper::assertStringContainsString("> HEAD / HTTP/1.1", $output);
            Helper::assertStringContainsString("< HTTP/1.1 200", $output);
            \fclose($res);
    }

    
    public function testEmitsProgressToFunction(): void
    {
        Server::flush();
        Server::enqueue(vec[new HM\Response()]);
        $a = new HCH\CurlMultiHandler();
            $request = new HM\Request('HEAD', Server::$url);
            $pt = new ProgressTestCallback();
            $promise = $a->handle($request, dict[RequestOptions::PROGRESS => $pt]);
            $promise->wait();
            expect($pt->isCalled())->toBeTrue();
    }


    private function addDecodeResponse(bool $withEncoding = true): string
    {
        $content = \gzencode('test') as string;
        $headers = dict['Content-Length' => vec[(string)\strlen($content)]];
        if ($withEncoding) {
            $headers['Content-Encoding'] = vec['gzip'];
        }
        $response = new HM\Response(200, $headers, $content);
        Server::flush();
        Server::enqueue(vec[$response]);
        return $content;
    }

    public function testDecodesGzippedResponses(): void
    {
        $this->addDecodeResponse();
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('GET', Server::$url);
            $promise = $handler->handle($request, dict[RequestOptions::DECODE_CONTENT => true]);
            $response = $promise->wait();
            expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
            if($response is HM\ResponseInterface) {
                Helper::assertEquals('test', $response->getBody()->__toString());
                $sent = Server::received()[0];
                Helper::assertFalse($sent->hasHeader('Accept-Encoding'));
            }
    }

    public function testReportsOriginalSizeAndContentEncodingAfterDecoding(): void
    {
        $this->addDecodeResponse();
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('GET', Server::$url);
            $promise = $handler->handle($request, dict[RequestOptions::DECODE_CONTENT => true]);
            $response = $promise->wait();
            expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
            if($response is HM\ResponseInterface) {
                Helper::assertSame(
                    'gzip',
                    $response->getHeaderLine('x-encoded-content-encoding')
                );
                Helper::assertSame(
                    \strlen(\gzencode('test') as string),
                    (int) $response->getHeaderLine('x-encoded-content-length')
                );
            }
    }

    public function testDecodesGzippedResponsesWithHeader(): void
    {
        $this->addDecodeResponse();
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('GET', Server::$url, dict['Accept-Encoding' => vec['gzip']]);
            $promise = $handler->handle($request, dict[RequestOptions::DECODE_CONTENT => true]);
            $response = $promise->wait();
            expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
            if($response is HM\ResponseInterface) {
                $sent = Server::received()[0];
                Helper::assertEquals('gzip', $sent->getHeaderLine('Accept-Encoding'));
                Helper::assertEquals('test', $response->getBody()->__toString());
                Helper::assertFalse($response->hasHeader('content-encoding'));
                Helper::assertTrue(
                    !$response->hasHeader('content-length') ||
                    $response->getHeaderLine('content-length') == $response->getBody()->getSize()
                );
            }
    }

    public function testDecodesGzippedResponsesWithHeaderForHeadRequest(): void
    {
        $this->addDecodeResponse();
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('HEAD', Server::$url, dict['Accept-Encoding' => vec['gzip']]);
            $promise = $handler->handle($request, dict[RequestOptions::DECODE_CONTENT => true]);
            $response = $promise->wait();
            $sent = Server::received()[0];
            Helper::assertEquals('gzip', $sent->getHeaderLine('Accept-Encoding'));

            expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
            if($response is HM\ResponseInterface) {
                // Verify that the content-length matches the encoded size.
                Helper::assertTrue(
                    !$response->hasHeader('content-length') ||
                    $response->getHeaderLine('content-length') == \strlen(\gzencode('test') as string)
                );
            }
    }


    public function testDoesNotForceDecode(): void
    {
        $content = $this->addDecodeResponse();
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('GET', Server::$url);
            $promise = $handler->handle($request, dict[RequestOptions::DECODE_CONTENT => false]);
            $response = $promise->wait();
            expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
            if($response is HM\ResponseInterface) {
                $sent = Server::received()[0];
                Helper::assertFalse($sent->hasHeader('Accept-Encoding'));
                Helper::assertEquals($content, $response->getBody()->__toString());
            }
    }

    public function testSavesToStream(): void
    {
        $stream = HM\Utils::streamFor(null);
        $this->addDecodeResponse();
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('GET', Server::$url);
            $response = $handler->handle($request, dict[
                RequestOptions::DECODE_CONTENT => true,
                RequestOptions::SINK           => $stream,
            ]);
            $response->wait();
            Helper::assertEquals('test', $stream->__toString());
    }

    public async function testSavesToFileOnDisk(): Awaitable<void>
    {
        $tmpfile = \tempnam(\sys_get_temp_dir(), 'testfile');
        $this->addDecodeResponse();
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('GET', Server::$url);
            $promise = $handler->handle($request, dict[
                RequestOptions::DECODE_CONTENT => true,
                RequestOptions::SINK           => $tmpfile,
            ]);
            $promise->wait();
            await Helper::assertStringEqualsFile($tmpfile, 'test');
            \unlink($tmpfile);
    }

    public function testDoesNotAddMultipleContentLengthHeaders(): void
    {
        $this->addDecodeResponse();
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('PUT', Server::$url, dict['Content-Length' => vec['3']], 'foo');
            $response = $handler->handle($request, dict[]);
            $response->wait();
            $sent = Server::received()[0];
            Helper::assertEquals('3', $sent->getHeaderLine('Content-Length'));
            Helper::assertFalse($sent->hasHeader('Transfer-Encoding'));
            Helper::assertEquals('foo', $sent->getBody()->__toString());
    }

    public function testSendsPostWithNoBodyOrDefaultContentType(): void
    {
        Server::flush();
        Server::enqueue(vec[new HM\Response()]);
        $handler = new HCH\CurlMultiHandler();
            $request = new HM\Request('POST', Server::$url);
            $promise = $handler->handle($request, dict[]);
            $promise->wait();
            $received = Server::received()[0];
            Helper::assertEquals('POST', $received->getMethod());
            Helper::assertFalse($received->hasHeader('content-type'));
            Helper::assertSame('0', $received->getHeaderLine('content-length'));
    }

    public function testHandles100Continue(): void
    {
        Server::flush();
        Server::enqueue(vec[
            new HM\Response(200, dict['Test' => vec['Hello'], 'Content-Length' => vec['4']], 'test'),
        ]);
        $request = new HM\Request('PUT', Server::$url, dict[
            'Expect' => vec['100-Continue']
        ], 'test');
        $handler = new HCH\CurlMultiHandler();
            $response = $handler->handle($request, dict[])->wait();
            expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
            if($response is HM\ResponseInterface) {
                Helper::assertSame(200, $response->getStatusCode());
                Helper::assertSame('OK', $response->getReasonPhrase());
                Helper::assertSame('Hello', $response->getHeaderLine('Test'));
                Helper::assertSame('4', $response->getHeaderLine('Content-Length'));
                Helper::assertSame('test', $response->getBody()->__toString());
            }
    }

    public function testSendsRequest(): void
    {
        Server::enqueue(vec[new HM\Response()]);
        $a = new HCH\CurlMultiHandler();
            $request = new HM\Request('GET', Server::$url);
            $response = $a->handle($request, dict[])->wait();
            expect($response)->toBeInstanceOf(HM\ResponseInterface::class);
            if($response is HM\ResponseInterface) {
                Helper::assertSame(200, $response->getStatusCode());
            }
    }

    public function testCanCancel(): void
    {
        Server::flush();
        $response = new HM\Response(200);
        Server::enqueue(vec(\array_fill_keys(\range(0, 10), $response)));
        $a = new HCH\CurlMultiHandler();
            $promises = vec[];
            for ($i = 0; $i < 10; $i++) {
                $promise = $a->handle(new HM\Request('GET', Server::$url), dict[]);
                $promise->cancel();
                $promises[] = $promise;
            }

            foreach ($promises as $p) {
                Helper::assertTrue(P\Is::rejected($p));
            }
    }

    public function testCannotCancelFinished(): void
    {
        Server::flush();
        Server::enqueue(vec[new HM\Response(200)]);
        $a = new HCH\CurlMultiHandler();
            $promise = $a->handle(new HM\Request('GET', Server::$url), dict[]);
            $promise->wait();
            $promise->cancel();
            Helper::assertTrue(P\Is::fulfilled($promise));
    }

    
    public function testDelaysConcurrently(): void
    {
        Server::flush();
        Server::enqueue(vec[new HM\Response()]);
        $a = new HCH\CurlMultiHandler();
            $expected = HC\Utils::currentTime() + (100 / 1000);
            $promise = $a->handle(new HM\Request('GET', Server::$url), dict[RequestOptions::DELAY => 100]);
            $promise->wait();
            Helper::assertGreaterThanOrEqual($expected, HC\Utils::currentTime());
    }
    
}

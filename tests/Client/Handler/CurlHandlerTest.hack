namespace HackHttp\Tests\Client\Handler;

use HackHttp\Tests\Helper;
use HackHttp\Tests\Server;

use namespace HackPromises as P;
use namespace HackHttp\Message as HM;
use namespace HackHttp\Client\Handler as HCH;
use namespace HackHttp\Client\Exception as HCE;
use namespace HackHttp\Client as HC;

use HackHttp\Client\Handler\CurlHandler;
use HackHttp\Client\RequestOptions;

use function Facebook\FBExpect\expect;
use type Facebook\HackTest\HackTest;
use HackHttp\HM\ResponseInterface;


/**
 * @covers HackHttp\Handler\CurlHandler
 */
class CurlHandlerTest extends HackTest
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

    public function testCreatesCurlErrors(): void
    {
        $handler = new CurlHandler();
        $request = new HM\Request('GET', 'http://localhost:123');

        expect(() ==> $handler->handle($request, dict[RequestOptions::TIMEOUT => 0.001, RequestOptions::CONNECT_TIMEOUT => 0.001])
            ->wait())->toThrow(HCE\ConnectException::class, 'cURL');
    }


    public function testDoesSleep(): void
    {
        $response = new HM\Response(200);
        Server::enqueue(vec[$response]);
        $a = new CurlHandler();
        $request = new HM\Request('GET', Server::$url);
        $s = HC\Utils::currentTime();
        $a->handle($request,dict[RequestOptions::DELAY => 0.1])->wait();
        Helper::assertGreaterThan(0.0001, HC\Utils::currentTime() - $s);
    }


    public function testUsesContentLengthWhenOverInMemorySize(): void
    {
        Server::flush();
        Server::enqueue(vec[new HM\Response()]);
        $stream = HM\Utils::streamFor(\str_repeat('.', 1000000));
        $handler = new CurlHandler();
        $request = new HM\Request(
            'PUT',
            Server::$url,
            dict['Content-Length' => vec[(string)1000000]],
            $stream
        );
        $handler->handle($request, dict[])->wait();
        $received = Server::received()[0];
        Helper::assertEquals('1000000', $received->getHeaderLine('Content-Length'));
        Helper::assertFalse($received->hasHeader('Transfer-Encoding'));
    }
}

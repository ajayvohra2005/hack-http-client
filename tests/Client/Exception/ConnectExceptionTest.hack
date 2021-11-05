namespace HackHttp\Tests\Client\Exception;

use HackHttp\Tests\Helper;
use HackHttp\Client\Exception\ConnectException;
use HackHttp\Message\Request;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\HackTest;

/**
 * @covers \GuzzleHttp\Exception\ConnectException
 */
class ConnectExceptionTest extends HackTest
{
    public function testHasRequest(): void
    {
        $req = new Request('GET', '/');
        $prev = new \Exception();
        $e = new ConnectException('foo', $req, $prev, dict['foo' => 'bar']);
        Helper::assertSame($req, $e->getRequest());
        Helper::assertSame('foo', $e->getMessage());
        Helper::assertSame('bar', $e->getHandlerContext()['foo']);
        Helper::assertSame($prev, $e->getPrevious());
    }
}

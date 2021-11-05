namespace HackHttp\Tests\Client\Exception;

use HackHttp\Tests\Helper;

use HackHttp\Client\Exception\BadResponseException;
use HackHttp\Message\Request;
use HackHttp\Message\Response;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\HackTest;

class BadResponseExceptionTest extends HackTest
{
    public function testHasNoResponse(): void
    {
        $req = new Request('GET', '/');
        $prev = new \Exception();
        $response = new Response();
        $e = new BadResponseException('foo', $req, $response, $prev);
        Helper::assertSame($req, $e->getRequest());
        Helper::assertSame($response, $e->getResponse());
        Helper::assertTrue($e->hasResponse());
        Helper::assertSame('foo', $e->getMessage());
        Helper::assertSame($prev, $e->getPrevious());
    }
}

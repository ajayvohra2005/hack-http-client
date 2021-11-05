namespace HackHttp\Tests\Client\Exception;

use HackHttp\Tests\Helper;

use HackHttp\Client\Exception\ClientException;
use HackHttp\Client\Exception\RequestException;
use HackHttp\Client\Exception\ServerException;
use namespace HackHttp\Message as HM;
use HackHttp\Message\Request;
use HackHttp\Message\Response;
use HackHttp\Message\Stream;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

/**
 * @covers \GuzzleHttp\Exception\RequestException
 */
class RequestExceptionTest extends HackTest
{
    public function testHasRequestAndResponse(): void
    {
        $req = new Request('GET', '/');
        $res = new Response(200);
        $e = new RequestException('foo', $req, $res);
        Helper::assertSame($req, $e->getRequest());
        Helper::assertSame($res, $e->getResponse());
        Helper::assertTrue($e->hasResponse());
        Helper::assertSame('foo', $e->getMessage());
    }

    public function testCreatesGenerateException(): void
    {
        $e = RequestException::create(new Request('GET', '/'));
        Helper::assertSame('Error completing request', $e->getMessage());
        Helper::assertInstanceOf(RequestException::class, $e);
    }

    public function testCreatesClientErrorResponseException(): void
    {
        $e = RequestException::create(new Request('GET', '/'), new Response(400));
        Helper::assertStringContainsString(
            'GET /',
            $e->getMessage()
        );
        Helper::assertStringContainsString(
            '400 Bad Request',
            $e->getMessage()
        );
        Helper::assertInstanceOf(ClientException::class, $e);
    }

    public function testCreatesServerErrorResponseException(): void
    {
        $e = RequestException::create(new Request('GET', '/'), new Response(500));
        Helper::assertStringContainsString(
            'GET /',
            $e->getMessage()
        );
        Helper::assertStringContainsString(
            '500 Internal Server Error',
            $e->getMessage()
        );
        Helper::assertInstanceOf(ServerException::class, $e);
    }

    public function testCreatesGenericErrorResponseException(): void
    {
        $e = RequestException::create(new Request('GET', '/'), new Response(300));
        Helper::assertStringContainsString(
            'GET /',
            $e->getMessage()
        );
        Helper::assertStringContainsString(
            '300 ',
            $e->getMessage()
        );
        Helper::assertInstanceOf(RequestException::class, $e);
    }

    public function dataPrintableResponses(): vec<(string)>
    {
        return vec[
            tuple('You broke the test!'),
            tuple('<h1>zlomený zkouška</h1>'),
            tuple('{"tester": "Philépe Gonzalez"}'),
            tuple("<xml>\n\t<text>Your friendly test</text>\n</xml>"),
            tuple('document.body.write("here comes a test");'),
            tuple("body:before {\n\tcontent: 'test style';\n}"),
        ];
    }

    <<DataProvider('dataPrintableResponses')>>
    public function testCreatesExceptionWithPrintableBodySummary(string $content): void
    {
        $response = new Response(
            500,
            dict[],
            $content
        );
        $e = RequestException::create(new Request('GET', '/'), $response);
        Helper::assertStringContainsString(
            $content,
            $e->getMessage()
        );
        Helper::assertInstanceOf(RequestException::class, $e);
    }

    public function testCreatesExceptionWithTruncatedSummary(): void
    {
        $content = \str_repeat('+', 121);
        $response = new Response(500, dict[], $content);
        $e = RequestException::create(new Request('GET', '/'), $response);
        $expected = \str_repeat('+', 120) . ' (truncated...)';
        Helper::assertStringContainsString($expected, $e->getMessage());
    }

    public function testExceptionMessageIgnoresEmptyBody(): void
    {
        $e = RequestException::create(new Request('GET', '/'), new Response(500));
        Helper::assertStringEndsWith('response', $e->getMessage());
    }

    public function testHasStatusCodeAsExceptionCode(): void
    {
        $e = RequestException::create(new Request('GET', '/'), new Response(442));
        Helper::assertSame(442, $e->getCode());
    }

    public function testWrapsRequestExceptions(): void
    {
        $e = new \Exception('foo');
        $r = new Request('GET', 'http://www.oo.com');
        $ex = RequestException::wrapException($r, $e);
        Helper::assertInstanceOf(RequestException::class, $ex);
        Helper::assertSame($e, $ex->getPrevious());
    }

    public function testDoesNotWrapExistingRequestExceptions(): void
    {
        $r = new Request('GET', 'http://www.oo.com');
        $e = new RequestException('foo', $r);
        $e2 = RequestException::wrapException($r, $e);
        Helper::assertSame($e, $e2);
    }

    public function testCanProvideHandlerContext(): void
    {
        $r = new Request('GET', 'http://www.oo.com');
        $e = new RequestException('foo', $r, null, null, dict['bar' => 'baz']);
        Helper::assertSame(dict['bar' => 'baz'], $e->getHandlerContext());
    }

    public function testObfuscateUrlWithUsername(): void
    {
        $r = new Request('GET', 'http://username@www.oo.com');
        $e = RequestException::create($r, new Response(500));
        Helper::assertStringContainsString('http://username@www.oo.com', $e->getMessage());
    }

    public function testObfuscateUrlWithUsernameAndPassword(): void
    {
        $r = new Request('GET', 'http://user:password@www.oo.com');
        $e = RequestException::create($r, new Response(500));
        Helper::assertStringContainsString('http://user:***@www.oo.com', $e->getMessage());
    }
}

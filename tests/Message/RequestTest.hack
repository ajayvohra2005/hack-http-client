namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use HackHttp\Message\Request;
use HackHttp\Message\Uri;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};
use HackHttp\Message\StreamInterface;

/**
 * @covers HackHttp\Message\MessageTrait
 * @covers HackHttp\Message\Request
 */
class RequestTest extends HackTest
{
    public function testRequestUriMayBeString(): void
    {
        $r = new Request('GET', '/');
        Helper::assertSame('/', $r->getUri()->__toString());
    }

    public function testRequestUriMayBeUri(): void
    {
        $uri = new Uri('/');
        $r = new Request('GET', $uri);
        Helper::assertSame($uri, $r->getUri());
    }

    public function testValidateRequestUri(): void
    {
        expect(() ==> new Request('GET', '///'))->toThrow(\InvalidArgumentException::class);
    }

    public function testCanConstructWithBody(): void
    {
        $r = new Request('GET', '/', dict[], 'baz');
        Helper::assertInstanceOf(StreamInterface::class, $r->getBody());
        Helper::assertSame('baz', $r->getBody()->__toString());
    }

    public function testNullBody(): void
    {
        $r = new Request('GET', '/', dict[], null);
        Helper::assertInstanceOf(StreamInterface::class, $r->getBody());
        Helper::assertSame('', $r->getBody()->__toString());
    }

    public function testFalseyBody(): void
    {
        $r = new Request('GET', '/', dict[], '0');
        Helper::assertInstanceOf(StreamInterface::class, $r->getBody());
        Helper::assertSame('0', $r->getBody()->__toString());
    }

    public function testCapitalizesMethod(): void
    {
        $r = new Request('get', '/');
        Helper::assertSame('GET', $r->getMethod());
    }

    public function testCapitalizesWithMethod(): void
    {
        $r = new Request('GET', '/');
        Helper::assertSame('PUT', $r->withMethod('put')->getMethod());
    }

    public function testWithUri(): void
    {
        $r1 = new Request('GET', '/');
        $u1 = $r1->getUri();
        $u2 = new Uri('http://www.example.com');
        $r2 = $r1->withUri($u2);
        Helper::assertNotSame($r1, $r2);
        Helper::assertSame($u2, $r2->getUri());
        Helper::assertSame($u1, $r1->getUri());
    }

    <<DataProvider('invalidMethodsProvider')>>
    public function testConstructWithInvalidMethods(string $method): void
    {
        expect(() ==> new Request($method, '/'))->toThrow(\InvalidArgumentException::class);
    }

    <<DataProvider('invalidMethodsProvider')>>
    public function testWithInvalidMethods(string $method): void
    {
        $r = new Request('get', '/');
        expect(() ==> $r->withMethod($method))->toThrow(\InvalidArgumentException::class);
    }

    public function invalidMethodsProvider(): vec<(mixed)>
    {
        return vec[
            tuple('')
        ];
    }

    public function testSameInstanceWhenSameUri(): void
    {
        $r1 = new Request('GET', 'http://foo.com');
        $r2 = $r1->withUri($r1->getUri());
        Helper::assertSame($r1, $r2);
    }

    public function testWithRequestTarget(): void
    {
        $r1 = new Request('GET', '/');
        $r2 = $r1->withRequestTarget('*');
        Helper::assertSame('*', $r2->getRequestTarget());
        Helper::assertSame('/', $r1->getRequestTarget());
    }

    public function testRequestTargetDoesNotAllowSpaces(): void
    {
        $r1 = new Request('GET', '/');
        expect(() ==> $r1->withRequestTarget('/foo bar'))->toThrow(\InvalidArgumentException::class);
    }

    public function testRequestTargetDefaultsToSlash(): void
    {
        $r1 = new Request('GET', '');
        Helper::assertSame('/', $r1->getRequestTarget());
        $r2 = new Request('GET', '*');
        Helper::assertSame('*', $r2->getRequestTarget());
        $r3 = new Request('GET', 'http://foo.com/bar baz/');
        Helper::assertSame('/bar%20baz/', $r3->getRequestTarget());
    }

    public function testBuildsRequestTarget(): void
    {
        $r1 = new Request('GET', 'http://foo.com/baz?bar=bam');
        Helper::assertSame('/baz?bar=bam', $r1->getRequestTarget());
    }

    public function testBuildsRequestTargetWithFalseyQuery(): void
    {
        $r1 = new Request('GET', 'http://foo.com/baz?0');
        Helper::assertSame('/baz?0', $r1->getRequestTarget());
    }

    public function testHostIsAddedFirst(): void
    {
        $r = new Request('GET', 'http://foo.com/baz?bar=bam', dict['Foo' => vec['Bar']]);
        Helper::assertSame(dict[
            'Host' => vec['foo.com'],
            'Foo'  => vec['Bar']
        ], $r->getHeaders());
    }

    public function testCanGetHeaderAsCsv(): void
    {
        $r = new Request('GET', 'http://foo.com/baz?bar=bam', dict[
            'Foo' => vec['a', 'b', 'c']
        ]);
        Helper::assertSame('a, b, c', $r->getHeaderLine('Foo'));
        Helper::assertSame('', $r->getHeaderLine('Bar'));
    }

    <<DataProvider('provideHeadersContainingNotAllowedChars')>>
    public function testContainsNotAllowedCharsOnHeaderField(string $header): void
    {
        $expected_exception_message = \sprintf('"%s" is not valid header name',$header);
        expect( () ==> new Request('GET', 'http://foo.com/baz?bar=bam', 
            dict[$header => vec['value']]))->toThrow(\InvalidArgumentException::class, $expected_exception_message);
    }

    public function provideHeadersContainingNotAllowedChars(): vec<(string)>
    {
        return vec[ 
                tuple(' key '), 
                tuple('key '), 
                tuple(' key'), 
                tuple('key/'), 
                tuple('key('), 
                tuple('key\\'), 
                tuple(' ')
            ];
    }

    <<DataProvider('provideHeadersContainsAllowedChar')>>
    public function testContainsAllowedCharsOnHeaderField(string $header): void
    {
        $r = new Request(
            'GET',
            'http://foo.com/baz?bar=bam',
            dict [
                $header => vec['value']
            ]
        );
        Helper::assertArrayHasKey($header, $r->getHeaders());
    }

    public function provideHeadersContainsAllowedChar(): vec<(string)>
    {
        return vec[
            tuple('key'),
            tuple('key#'),
            tuple('key$'),
            tuple('key%'),
            tuple('key&'),
            tuple('key*'),
            tuple('key+'),
            tuple('key.'),
            tuple('key^'),
            tuple('key_'),
            tuple('key|'),
            tuple('key~'),
            tuple('key!'),
            tuple('key-'),
            tuple("key'"),
            tuple('key`')
        ];
    }

    public function testHostIsNotOverwrittenWhenPreservingHost(): void
    {
        $r = new Request('GET', 'http://foo.com/baz?bar=bam', dict['Host' => vec['a.com']]);
        Helper::assertSame(dict['Host' => vec['a.com']], $r->getHeaders());
        $r2 = $r->withUri(new Uri('http://www.foo.com/bar'), true);
        Helper::assertSame('a.com', $r2->getHeaderLine('Host'));
    }

    public function testWithUriSetsHostIfNotSet(): void
    {
        $r = new Request('GET', 'http://foo.com/baz?bar=bam');
        $r1 = $r->withoutHeader('Host');
        Helper::assertSame(dict[], $r1->getHeaders());
        $r2 = $r->withUri(new Uri('http://www.baz.com/bar'), true);
        Helper::assertSame('foo.com', $r2->getHeaderLine('Host'));
    }

    public function testOverridesHostWithUri(): void
    {
        $r = new Request('GET', 'http://foo.com/baz?bar=bam');
        Helper::assertSame(dict['Host' => vec['foo.com']], $r->getHeaders());
        $r2 = $r->withUri(new Uri('http://www.baz.com/bar'));
        Helper::assertSame('www.baz.com', $r2->getHeaderLine('Host'));
    }

    public function testAggregatesHeaders(): void
    {
        $r = new Request('GET', '', dict[
            'ZOO' => vec['zoobar'],
            'zoo' => vec['foobar', 'zoobar']
        ]);
        Helper::assertSame(dict['ZOO' => vec['zoobar', 'foobar', 'zoobar']], $r->getHeaders());
        Helper::assertSame('zoobar, foobar, zoobar', $r->getHeaderLine('zoo'));
    }

    public function testAddsPortToHeader(): void
    {
        $r = new Request('GET', 'http://foo.com:8124/bar');
        Helper::assertSame('foo.com:8124', $r->getHeaderLine('host'));
    }

    public function testAddsPortToHeaderAndReplacePreviousPort(): void
    {
        $r = new Request('GET', 'http://foo.com:8124/bar');
        $r = $r->withUri(new Uri('http://foo.com:8125/bar'));
        Helper::assertSame('foo.com:8125', $r->getHeaderLine('host'));
    }
}

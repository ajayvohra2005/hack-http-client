namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use HackHttp\Message\Stream;
use HackHttp\Message\PumpStream;
use HackHttp\Message\NoSeekStream;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};
use HackHttp\Message\StreamInterface;

use namespace HH\Lib\OS;

class UtilsTest extends HackTest
{
    public function testCopiesToString(): void
    {
        $s = HM\Utils::streamFor('foobaz');
        Helper::assertSame('foobaz', HM\Utils::copyToString($s));
        $s->seek(0);
        Helper::assertSame('foo', HM\Utils::copyToString($s, 3));
        Helper::assertSame('baz', HM\Utils::copyToString($s, 3));
        Helper::assertSame('', HM\Utils::copyToString($s));
    }

    public function testCopiesToStream(): void
    {
        $s1 = HM\Utils::streamFor('foobaz');
        $s2 = HM\Utils::streamFor('');
        HM\Utils::copyToStream($s1, $s2);
        Helper::assertSame('foobaz', $s2->__toString());
        $s2 = HM\Utils::streamFor('');
        $s1->seek(0);
        HM\Utils::copyToStream($s1, $s2, 3);
        Helper::assertSame('foo', $s2->__toString());
        HM\Utils::copyToStream($s1, $s2, 3);
        Helper::assertSame('foobaz', $s2->__toString());
    }



    public function testReadsLines(): void
    {
        $s = HM\Utils::streamFor("foo\nbaz\nbar");
        Helper::assertSame("foo\n", HM\Utils::readLine($s));
        Helper::assertSame("baz\n", HM\Utils::readLine($s));
        Helper::assertSame('bar', HM\Utils::readLine($s));
    }

    public function testReadsLinesUpToMaxLength(): void
    {
        $s = HM\Utils::streamFor("12345\n");
        Helper::assertSame('123', HM\Utils::readLine($s, 4));
        Helper::assertSame("45\n", HM\Utils::readLine($s));
    }

    public function testReadLinesEof(): void
    {
        // Should return empty string on EOF
        $s = HM\Utils::streamFor("foo\nbar");
        while (!$s->eof()) {
            HM\Utils::readLine($s);
        }
        Helper::assertSame('', HM\Utils::readLine($s));
    }


    public function testCalculatesHash(): void
    {
        $s = HM\Utils::streamFor('foobazbar');
        Helper::assertSame(\md5('foobazbar'), HM\Utils::hash($s, 'md5'));
    }

    public function testCalculatesHashThrowsWhenSeekFails(): void
    {
        $s = new NoSeekStream(HM\Utils::streamFor('foobazbar'));
        $s->read(2);

        expect(() ==> HM\Utils::hash($s, 'md5'))->toThrow(\RuntimeException::class);
    }

    public function testCalculatesHashSeeksToOriginalPosition(): void
    {
        $s = HM\Utils::streamFor('foobazbar');
        $s->seek(4);
        Helper::assertSame(\md5('foobazbar'), HM\Utils::hash($s, 'md5'));
        Helper::assertSame(4, $s->tell());
    }


    public function testThrowsExceptionForInvalidPath(): void
    {
        expect(() ==> HM\Utils::getFileHandle("/path/to/does/not/exist", null))->toThrow(OS\NotFoundException::class, 'ENOENT(2): Errno 2: No such file or directory');
    }

    public function testValidatesUri(): void
    {
        expect(() ==> HM\Utils::uriFor(vec[]))->toThrow(\InvalidArgumentException::class);
    }

    public function testCreatesWithFactory(): void
    {
        $stream = HM\Utils::streamFor('foo');
        Helper::assertInstanceOf(Stream::class, $stream);
        Helper::assertSame('foo', $stream->getContents());
        $stream->close();
    }

    public function testFactoryCreatesFromEmptyString(): void
    {
        $s = HM\Utils::streamFor(null);
        Helper::assertInstanceOf(Stream::class, $s);
    }

    public function testFactoryCreatesFromNull(): void
    {
        $s = HM\Utils::streamFor(null);
        Helper::assertInstanceOf(Stream::class, $s);
    }

    public function testCreatePassesThrough(): void
    {
        $s = HM\Utils::streamFor('foo');
        Helper::assertSame($s, HM\Utils::streamFor($s));
    }

    public function testThrowsExceptionForUnknown(): void
    {
        expect(() ==> HM\Utils::streamFor(new \stdClass()))->toThrow(\InvalidArgumentException::class);
    }

    public function testReturnsCustomMetadata(): void
    {
        $s = HM\Utils::streamFor('foo', shape('size' => 0, 'metadata' => dict['hwm' => 3]));
        Helper::assertSame(3, $s->getMetadata('hwm'));
        $m = $s->getMetadata();
        if($m is dict<_,_>) {
            Helper::assertArrayHasKey('hwm', $m);
        }
    }

    public function testCanSetSize(): void
    {
        $s = HM\Utils::streamFor('', shape('size' => 10, 'metadata' => dict[]));
        Helper::assertSame(10, $s->getSize());
    }

    public function testCanCreateIteratorBasedStream(): void
    {
        $a = new \ArrayIterator(vec['foo', 'bar', '123']);
        $p = HM\Utils::streamFor($a);
        Helper::assertInstanceOf(PumpStream::class, $p);
        Helper::assertSame('foo', $p->read(3));
        Helper::assertFalse($p->eof());
        Helper::assertSame('b', $p->read(1));
        Helper::assertSame('a', $p->read(1));
        Helper::assertSame('r12', $p->read(3));
        Helper::assertFalse($p->eof());
        Helper::assertSame('3', $p->getContents());
        Helper::assertTrue($p->eof());
        Helper::assertSame(9, $p->tell());
    }

    public function testConvertsRequestsToStrings(): void
    {
        $request = new HM\Request('PUT', 'http://foo.com/hi?123', dict[
            'Baz' => vec['bar'],
            'Qux' => vec['ipsum'],
        ], 'hello', '1.0');
        Helper::assertSame(
            "PUT /hi?123 HTTP/1.0\r\nHost: foo.com\r\nBaz: bar\r\nQux: ipsum\r\n\r\nhello",
            HM\Message::toString($request)
        );
    }

    public function testConvertsResponsesToStrings(): void
    {
        $response = new HM\Response(200, dict[
            'Baz' => vec['bar'],
            'Qux' => vec['ipsum'],
        ], 'hello', '1.0', 'FOO');
        Helper::assertSame(
            "HTTP/1.0 200 FOO\r\nBaz: bar\r\nQux: ipsum\r\n\r\nhello",
            HM\Message::toString($response)
        );
    }

    public function testCorrectlyRendersSetCookieHeadersToString(): void
    {
        $response = new HM\Response(200, dict[
            'Set-Cookie' => vec['bar','baz','qux']
        ], 'hello', '1.0', 'FOO');
        Helper::assertSame(
            "HTTP/1.0 200 FOO\r\nSet-Cookie: bar\r\nSet-Cookie: baz\r\nSet-Cookie: qux\r\n\r\nhello",
            HM\Message::toString($response)
        );
    }

    public function testCanModifyRequestWithUri(): void
    {
        $r1 = new HM\Request('GET', 'http://foo.com');
        $r2 = HM\Utils::modifyRequest($r1, dict[
            'uri' => new HM\Uri('http://www.foo.com'),
        ]);
        Helper::assertSame('http://www.foo.com', $r2->getUri()->__toString());
        Helper::assertSame('www.foo.com', $r2->getHeaderLine('host'));
    }
    
    public function testCanModifyRequestWithUriAndPort(): void
    {
        $r1 = new HM\Request('GET', 'http://foo.com:8000');
        $r2 = HM\Utils::modifyRequest($r1, dict[
            'uri' => new HM\Uri('http://www.foo.com:8000'),
        ]);
        Helper::assertSame('http://www.foo.com:8000', $r2->getUri()->__toString());
        Helper::assertSame('www.foo.com:8000', (string)$r2->getHeaderLine('host'));
    }

    public function testCanModifyRequestWithCaseInsensitiveHeader(): void
    {
        $r1 = new HM\Request('GET', 'http://foo.com', dict['User-agent' => vec['foo']]);
        $r2 = HM\Utils::modifyRequest($r1, dict['set_headers' => dict['User-Agent' => vec['bar']]]);
        Helper::assertSame('bar', $r2->getHeaderLine('User-Agent'));
        Helper::assertSame('bar', $r2->getHeaderLine('User-agent'));
    }

    public function testReturnsAsIsWhenNoChanges(): void
    {
        $r1 = new HM\Request('GET', 'http://foo.com');
        $r2 = HM\Utils::modifyRequest($r1, dict[]);
        Helper::assertInstanceOf(HM\Request::class, $r2);
    }

    public function testReturnsUriAsIsWhenNoChanges(): void
    {
        $r1 = new HM\Request('GET', 'http://foo.com');
        $r2 = HM\Utils::modifyRequest($r1, dict['set_headers' => dict['foo' => vec['bar']]]);
        Helper::assertNotSame($r1, $r2);
        Helper::assertSame('bar', $r2->getHeaderLine('foo'));
    }

    public function testRemovesHeadersFromMessage(): void
    {
        $r1 = new HM\Request('GET', 'http://foo.com', dict['foo' => vec['bar']]);
        $r2 = HM\Utils::modifyRequest($r1, dict['remove_headers' => vec['foo']]);
        Helper::assertNotSame($r1, $r2);
        Helper::assertFalse($r2->hasHeader('foo'));
    }

    public function testAddsQueryToUri(): void
    {
        $r1 = new HM\Request('GET', 'http://foo.com');
        $r2 = HM\Utils::modifyRequest($r1, dict['query' => 'foo=bar']);
        Helper::assertNotSame($r1, $r2);
        Helper::assertSame('foo=bar', $r2->getUri()->getQuery());
    }

    public function testModifyRequestKeepInstanceOfRequest(): void
    {
        $r1 = new HM\Request('GET', 'http://foo.com');
        $r2 = HM\Utils::modifyRequest($r1, dict['remove_headers' => vec['non-existent']]);
        Helper::assertInstanceOf(HM\Request::class, $r2);
    }
}

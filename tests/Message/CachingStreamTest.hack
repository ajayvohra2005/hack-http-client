namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use HackHttp\Message\CachingStream;
use HackHttp\Message\Stream;
use HackHttp\Message\StreamInterface;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

/**
 * @covers HackHttp\Message\CachingStream
 */
class CachingStreamTest extends HackTest
{
    /** @var CachingStream */
    private ?CachingStream $body;
    /** @var StreamInterface */
    private ?StreamInterface $decorated;

    <<__Override>>
    public async function beforeEachTestAsync(): Awaitable<void> 
    {
        $this->decorated = HM\Utils::streamFor('testing');
        $this->body = new CachingStream($this->decorated);
    }

    <<__Override>>
    public async function afterEachTestAsync(): Awaitable<void> 
    {
        if($this->decorated) {
            $this->decorated->close();
        }

        if($this->body) {
            $this->body->close();
        }
    }

    public function testUsesRemoteSizeIfPossible(): void
    {
        $body = HM\Utils::streamFor('test');
        $caching = new CachingStream($body);
        Helper::assertSame(4, $caching->getSize());
    }

    public function testReadsUntilCachedToByte(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        if($body is nonnull) {
           $body->seek(5);
            Helper::assertSame('n',$body->read(1));
           $body->seek(0);
            Helper::assertSame('t',$body->read(1));
        }
    }

    public function testCanSeekNearEndWithSeekEnd(): void
    {
        $baseStream = HM\Utils::streamFor(\implode('', \range('a', 'z')));
        $cached = new CachingStream($baseStream);
        $cached->seek(-1, \SEEK_END);
        Helper::assertSame(25, $baseStream->tell());
        Helper::assertSame('z', $cached->read(1));
        Helper::assertSame(26, $cached->getSize());
    }

    public function testCanSeekToEndWithSeekEnd(): void
    {
        $baseStream = HM\Utils::streamFor(\implode('', \range('a', 'z')));
        $cached = new CachingStream($baseStream);
        $cached->seek(0, \SEEK_END);
        Helper::assertSame(26, $baseStream->tell());
        Helper::assertSame('', $cached->read(1));
        Helper::assertSame(26, $cached->getSize());
    }

    public function testRewind(): void
    {
        $a = HM\Utils::streamFor('foo');
        $d = new CachingStream($a);
        Helper::assertSame('foo', $d->read(3));
        $d->rewind();
        Helper::assertSame('foo', $d->read(3));
    }

    public function testCanSeekToReadBytes(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        if($body is nonnull) {
            Helper::assertSame('te',$body->read(2));
            $body->seek(0);
            Helper::assertSame('test',$body->read(4));
            Helper::assertSame(4,$body->tell());
            $body->seek(2);
            Helper::assertSame(2,$body->tell());
            $body->seek(2, \SEEK_CUR);
            Helper::assertSame(4,$body->tell());
            Helper::assertSame('ing',$body->read(3));
        }
    }

    public function testCanSeekToReadBytesWithPartialBodyReturned(): void
    {
        $this->decorated = HM\Utils::streamFor(null);
        $decorated = $this->decorated;
        expect($decorated)->toNotBeNull();

        if($decorated) {
            $decorated->write("testing");
            $decorated->seek(0);

            $body = new CachingStream($decorated);

            Helper::assertSame(0,$body->tell());
            $body->seek(4, \SEEK_SET);
            Helper::assertSame(4,$body->tell());
            $body->seek(0);
            Helper::assertSame('test',$body->read(4));
        }
    }

    public function testWritesToBufferStream(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        if($body is nonnull) {
            $body->read(2);
            $body->write('hi');
            $body->seek(0);
            Helper::assertSame('tehiing', $body->__toString());
        }
    }

    public function testSkipsOverwrittenBytes(): void
    {
        $decorated = HM\Utils::streamFor(
            \implode("\n", \array_map(($n) ==> {
                return \str_pad((string)$n, 4, '0', \STR_PAD_LEFT);
            }, \range(0, 25)))
        );

        $body = new CachingStream($decorated);

        Helper::assertSame("0000\n", HM\Utils::readLine($body));
        Helper::assertSame("0001\n", HM\Utils::readLine($body));
        // Write over part of the body yet to be read, so skip some bytes
        Helper::assertSame(5, $body->write("TEST\n"));
        // Read, which skips bytes, then reads
        Helper::assertSame("0003\n", HM\Utils::readLine($body));
        Helper::assertSame("0004\n", HM\Utils::readLine($body));
        Helper::assertSame("0005\n", HM\Utils::readLine($body));

        // Overwrite part of the cached body (so don't skip any bytes)
        $body->seek(5);
        Helper::assertSame(5, $body->write("ABCD\n"));
        Helper::assertSame("TEST\n", HM\Utils::readLine($body));
        Helper::assertSame("0003\n", HM\Utils::readLine($body));
        Helper::assertSame("0004\n", HM\Utils::readLine($body));
        Helper::assertSame("0005\n", HM\Utils::readLine($body));
        Helper::assertSame("0006\n", HM\Utils::readLine($body));
        Helper::assertSame(5, $body->write("1234\n"));

        // Seek to 0 and ensure the overwritten bit is replaced
        $body->seek(0);
        Helper::assertSame("0000\nABCD\nTEST\n0003\n0004\n0005\n0006\n1234\n0008\n0009\n", $body->read(50));

        // Ensure that casting it to a string does not include the bit that was overwritten
        Helper::assertStringContainsString("0000\nABCD\nTEST\n0003\n0004\n0005\n0006\n1234\n0008\n0009\n", $body->__toString());
    }

    public function testClosesBothStreams(): void
    {
        $a = HM\Utils::streamFor(null);
        $a->write("Testing stream");
        $a->seek(0);
        $d = new CachingStream($a);
        $d->close();
        expect(() ==> $d->read(null))->toThrow(\RuntimeException::class, "Stream is detached");
    }

    public function testEnsuresValidWhence(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        if($body is nonnull) {
            expect(() ==>$body->seek(10, -123456))->toThrow(\InvalidArgumentException::class, 'Invalid whence');
        }
    }
}

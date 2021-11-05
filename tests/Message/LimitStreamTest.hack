namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use HackHttp\Message\FnStream;
use HackHttp\Message\LimitStream;
use HackHttp\Message\NoSeekStream;
use HackHttp\Message\Stream;
use HackHttp\Message\StreamInterface;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

/**
 * @covers HackHttp\Message\LimitStream
 */
class LimitStreamTest extends HackTest
{
    /** @var LimitStream */
    private ?LimitStream $body;

    /** @var StreamInterface */
    private ?StreamInterface $decorated;

    <<__Override>>
    public async function beforeEachTestAsync(): Awaitable<void> 
    {
        $this->decorated = HM\Utils::streamFor(null);
        $decorated = $this->decorated;

        if($decorated is null) {
            throw new \RuntimeException("Decorated stream is null");
        }

        $decorated->write("This is a test of Limit stream");
        $this->body = new LimitStream($decorated, 10, 3);
    }

    public function testReturnsSubset(): void 
    {
        $body = new LimitStream(HM\Utils::streamFor('foo'), -1, 1);
        Helper::assertSame('oo', $body->__toString());
        Helper::assertTrue($body->eof());
        $body->seek(0);
        Helper::assertFalse($body->eof());
        Helper::assertSame('oo', $body->read(100));
        Helper::assertSame('', $body->read(1));
        Helper::assertTrue($body->eof());
    }

    public function testReturnsSubsetWhenCastToString(): void
    {
        $body = HM\Utils::streamFor('foo_baz_bar');
        $limited = new LimitStream($body, 3, 4);
        Helper::assertSame('baz', $limited->__toString());
    }

    public function testReturnsSubsetOfEmptyBodyWhenCastToString(): void
    {
        $body = HM\Utils::streamFor('01234567891234');
        $limited = new LimitStream($body, 0, 10);
        Helper::assertSame('', $limited->__toString());
    }

    public function testReturnsSpecificSubsetOBodyWhenCastToString(): void
    {
        $body = HM\Utils::streamFor('0123456789abcdef');
        $limited = new LimitStream($body, 3, 10);
        Helper::assertSame('abc', $limited->__toString());
    }

    public function testSeeksWhenConstructed(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        if($body is nonnull) {
            Helper::assertSame(0, $body->tell());
            expect($this->decorated)->toNotBeNull();
            if($this->decorated is nonnull) {
                Helper::assertSame(3, $this->decorated->tell());
            }
        }
    }

    public function testAllowsBoundedSeek(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        $decorated = $this->decorated;
        if($body is nonnull && $decorated is nonnull) {
            $body->seek(100);
            Helper::assertSame(10, $body->tell());
            Helper::assertSame(13, $decorated->tell());
            $body->seek(0);
            Helper::assertSame(0, $body->tell());
            Helper::assertSame(3, $decorated->tell());
            try {
                $body->seek(-10);
                self::fail();
            } catch (\RuntimeException $e) {
            }
            Helper::assertSame(0, $body->tell());
            Helper::assertSame(3, $decorated->tell());
            $body->seek(5);
            Helper::assertSame(5, $body->tell());
            Helper::assertSame(8, $decorated->tell());
            // Fail
            try {
                $body->seek(1000, \SEEK_END);
                self::fail();
            } catch (\RuntimeException $e) {
            }
        }
    }

    public function testReadsOnlySubsetOfData(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        $decorated = $this->decorated;
        if($body is nonnull && $decorated is nonnull) {
            $data = $body->read(100);
            Helper::assertSame(10, \strlen($data));
            Helper::assertSame('', $body->read(1000));

            $body->setOffset(10);
            $newData = $body->read(100);
            Helper::assertSame(10, \strlen($newData));
            Helper::assertNotSame($data, $newData);
        }
    }

    public function testThrowsWhenCurrentGreaterThanOffsetSeek(): void
    {
        $a = HM\Utils::streamFor('foo_bar');
        $b = new NoSeekStream($a);
        $c = new LimitStream($b);
        $a->getContents();
        expect(() ==> $c->setOffset(2))->toThrow(\RuntimeException::class, 'Could not seek to stream offset 2');
    }

    public function testCanGetContentsWithoutSeeking(): void
    {
        $a = HM\Utils::streamFor('foo_bar');
        $b = new NoSeekStream($a);
        $c = new LimitStream($b);
        Helper::assertSame('foo_bar', $c->getContents());
    }

    public function testClaimsConsumedWhenReadLimitIsReached(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        if($body is nonnull) {
            Helper::assertFalse($body->eof());
            $body->read(1000);
            Helper::assertTrue($body->eof());
        }
    }

    public function testContentLengthIsBounded(): void
    {
        expect($this->body)->toNotBeNull();
        $body = $this->body;
        if($body is nonnull) {
            Helper::assertSame(10, $body->getSize());
        }
    }

    public function testGetContentsIsBasedOnSubset(): void
    {
        $body = new LimitStream(HM\Utils::streamFor('foobazbar'), 3, 3);
        Helper::assertSame('baz', $body->getContents());
    }

    public function testLengthLessOffsetWhenNoLimitSize(): void
    {
        $a = HM\Utils::streamFor('foo_bar');
        $b = new LimitStream($a, -1, 4);
        Helper::assertSame(3, $b->getSize());
    }
}

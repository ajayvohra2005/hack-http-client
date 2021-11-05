namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use HackHttp\Message\NoSeekStream;
use HackHttp\Message\Stream;
use HackHttp\Message\Utils;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};
use HackHttp\Message\StreamInterface;

use namespace HH\Lib\IO;

/**
 * @covers HackHttp\Message\NoSeekStream
 * @covers HackHttp\Message\StreamDecoratorTrait
 */
class NoSeekStreamTest extends HackTest
{
    public function testCannotSeek(): void
    {
        $stream = Utils::streamFor(null);
        $wrapped = new NoSeekStream($stream);
        Helper::assertFalse($wrapped->isSeekable());
        expect(() ==> $wrapped->seek(2))->toThrow(\RuntimeException::class, 'Cannot seek a NoSeekStream');
    }

    public function testToStringDoesNotSeek(): void
    {
        $s = Utils::streamFor('foo');
        $s->seek(1);
        $wrapped = new NoSeekStream($s);
        Helper::assertSame('oo', $wrapped->__toString());
        $wrapped->close();
    }
}

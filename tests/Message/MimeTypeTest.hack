namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

class MimeTypeTest extends HackTest
{
    public function testDetermineFromExtension(): void
    {
        Helper::assertNull(HM\MimeType::fromExtension('not-a-real-extension'));
        Helper::assertSame('application/json', HM\MimeType::fromExtension('json'));
    }

    public function testDetermineFromFilename(): void
    {
        Helper::assertSame(
            'image/jpeg',
            HM\MimeType::fromFilename('/tmp/images/IMG034821.JPEG')
        );
    }
}

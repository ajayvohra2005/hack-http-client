namespace HackHttp\Tests;

use namespace HH;
use namespace HH\Lib\C;
use namespace HH\Lib\{File, IO, Str};

use function Facebook\FBExpect\expect; 
use type Facebook\HackTest\HackTest;

final class Helper
{

    public  static  function assertCount(int $count, Container<mixed> $container, string $msg=''): void
    {
        expect(C\count($container))->toBeSame($count);
    }

    public static function assertStringEndsWith(string $suffix, string $string, string $msg=''): void
    {
        expect(Str\ends_with($string, $suffix))->toBeTrue($msg);
    }

    public  static async function assertStringEqualsFile(string $expectedFile, string $actual, string $msg=''): Awaitable<void>
    {
        $handle = File\open_read_only($expectedFile);
        $expected = await $handle->readAllAsync();
        expect($expected)->toBeSame($actual, $msg);
    }

    public static function assertGreaterThanOrEqual(num $expected, num $actual, string $msg=''): void
    {
        expect($actual)->toBeGreaterThanOrEqualTo($expected);
    }

    public static function assertGreaterThan(num $expected, num $actual, string $msg=''): void
    {
        expect($actual)->toBeGreaterThan($expected, $msg);
    }
    
    public static function assertContains(mixed $needle, mixed $haystack, string $msg = ''): void
    {
        if(HH\is_any_array($haystack)) {
            expect(C\contains($haystack, $needle))->toBeTrue($msg);
        } else {
            throw new \RuntimeException("Container is not any array");
        }
    }

    public static function assertStringContainsString(string $needle, string $haystack, string $msg=''): void
    {
        expect($haystack)->toContainSubstring($needle, $msg);
    }
    
    public static function assertNotEmpty(mixed $expected, string $msg=''): void
    {
        expect($expected)->toNotBeEmpty($msg);
    }
    
    public static function assertFileExists(string $fname, string $msg=''): void
    {
        expect(\file_exists($fname))->toBeTrue($msg);
    }
    public static function assertIsArray(mixed $expected, string $msg=''): void
    {
        expect(HH\is_any_array($expected))->toBeTrue($msg);
    }

    public static function assertEquals(mixed $expected, mixed $actual, string $msg=''): void
    {
        expect($expected)->toBePHPEqual($actual, $msg);
    }
    
    public static function assertArrayHasKey(arraykey $key, dict<arraykey, mixed> $array, string $msg=''): void
    {
        expect($array)->toContainKey($key, $msg);
    }

    public static function assertInstanceOf(classname<mixed> $class_or_interface, mixed $expected, string $msg=''): void
    {
        expect($expected)->toBeInstanceOf($class_or_interface, $msg);
    }

    public static function assertSame(mixed $expected, mixed $actual, string $msg = ''): void
    {
       expect($actual)->toBeSame($expected, $msg);
    }

     public static function assertNotSame(mixed $expected, mixed $actual, string $msg = ''): void
    {
       expect($actual)->toNotBeSame($expected, $msg);
    }

    public static function assertNull(mixed $expected, string $msg = ''): void
    {
       expect($expected)->toBeNull($msg);
    }

    public static function assertTrue(bool $condition, string $msg = ''): void
    {
        expect($condition)->toBeTrue($msg);
    }

    public static function assertFalse(bool $condition, string $msg = ''): void
    {
        expect($condition)->toBeFalse($msg);
    }

}

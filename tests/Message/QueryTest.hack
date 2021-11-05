namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

class QueryTest extends HackTest
{
    public function parseQueryProvider(): vec<(string, dict<arraykey, mixed>)>
    {
        return vec[
            // Does not need to parse when the string is empty
            tuple('', dict[]),
            // Can parse mult-values items
            tuple('q=a&q=b', dict['q' => vec['a', 'b']]),
            // Can parse multi-valued items that use numeric indices
            tuple('q[0]=a&q[1]=b', dict['q[0]' => 'a', 'q[1]' => 'b']),
            // Can parse duplicates and does not include numeric indices
            tuple('q[]=a&q[]=b', dict['q[]' => vec['a', 'b']]),
            // Ensures that the value of "q" is an array even though one value
            tuple('q[]=a', dict['q[]' => 'a']),
            // Does not modify "." to "_" like PHP's parse_str()
            tuple('q.a=a&q.b=b', dict['q.a' => 'a', 'q.b' => 'b']),
            // Can decode %20 to " "
            tuple('q%20a=a%20b', dict['q a' => 'a b']),
            // Can parse funky strings with no values by assigning each to null
            tuple('q&a', dict['q' => null, 'a' => null]),
            // Does not strip trailing equal signs
            tuple('data=abc=', dict['data' => 'abc=']),
            // Can store duplicates without affecting other values
            tuple('foo=a&foo=b&?µ=c', dict['foo' => vec['a', 'b'], '?µ' => 'c']),
            // Sets value to null when no "=" is present
            tuple('foo', dict['foo' => null]),
            // Preserves "0" keys.
            tuple('0', dict['0' => null]),
            // Sets the value to an empty string when "=" is present
            tuple('0=', dict['0' => '']),
            // Preserves falsey keys
            tuple('var=0', dict['var' => '0']),
            tuple('a[b][c]=1&a[b][c]=2', dict['a[b][c]' => vec['1', '2']]),
            tuple('a[b]=c&a[d]=e', dict['a[b]' => 'c', 'a[d]' => 'e']),
            // Ensure it doesn't leave things behind with repeated values
            // Can parse mult-values items
            tuple('q=a&q=b&q=c', dict['q' => vec['a', 'b', 'c']]),
        ];
    }

    <<DataProvider('parseQueryProvider')>>
    public function testParsesQueries(string $input, dict<arraykey, mixed> $output): void
    {
        $result = HM\Query::parse($input);
        Helper::assertSame($output, $result);
    }

    public function testDoesNotDecode(): void
    {
        $str = 'foo%20=bar';
        $data = HM\Query::parse($str, false);
        Helper::assertSame(dict['foo%20' => 'bar'], $data);
    }

    <<DataProvider('parseQueryProvider')>>
    public function testParsesAndBuildsQueries(string $input): void
    {
        $result = HM\Query::parse($input, false);
        Helper::assertSame($input, HM\Query::build($result, false));
    }

    public function testEncodesWithRfc1738(): void
    {
        $str = HM\Query::build(dict['foo bar' => 'baz+'], \PHP_QUERY_RFC1738);
        Helper::assertSame('foo+bar=baz%2B', $str);
    }

    public function testEncodesWithRfc3986(): void
    {
        $str = HM\Query::build(dict['foo bar' => 'baz+'], \PHP_QUERY_RFC3986);
        Helper::assertSame('foo%20bar=baz%2B', $str);
    }

    public function testDoesNotEncode(): void
    {
        $str = HM\Query::build(dict['foo bar' => 'baz+'], false);
        Helper::assertSame('foo bar=baz+', $str);
    }

    public function testCanControlDecodingType(): void
    {
        $result = HM\Query::parse('var=foo+bar', \PHP_QUERY_RFC3986);
        Helper::assertSame('foo+bar', $result['var']);
        $result = HM\Query::parse('var=foo+bar', \PHP_QUERY_RFC1738);
        Helper::assertSame('foo bar', $result['var']);
    }

    public function testBuildBooleans(): void
    {
        $data = dict[
            'true' => true,
            'false' => false
        ];
        Helper::assertEquals(\http_build_query($data), HM\Query::build($data));

        $data = dict[
            'foo' => vec[true, 'true'],
            'bar' => vec[false, 'false']
        ];
        Helper::assertEquals('foo=1&foo=true&bar=0&bar=false', HM\Query::build($data, \PHP_QUERY_RFC1738));
    }
}

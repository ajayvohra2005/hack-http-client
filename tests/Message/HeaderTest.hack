namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

class HeaderTest extends HackTest
{
    public function parseParamsProvider(): vec<(string, vec<dict<string, vec<string>>>)>
    {
        $res1 = vec[
            dict[
                '<http:/.../front.jpeg>' => vec[''],
                'rel' => vec['front'],
                'type' => vec['image/jpeg'],
            ],
            dict[
                '<http://.../back.jpeg>' => vec[''],
                'rel' => vec['back'],
                'type' => vec['image/jpeg'],
            ],
        ];
        return vec[
            tuple(
                '<http:/.../front.jpeg>; rel="front"; type="image/jpeg", <http://.../back.jpeg>; rel=back; type="image/jpeg"',
                $res1,
            ),
            tuple(
                '<http:/.../front.jpeg>; rel="front"; type="image/jpeg",<http://.../back.jpeg>; rel=back; type="image/jpeg"',
                $res1,
            ),
            tuple(
                'foo="baz"; bar=123, boo, test="123", foobar="foo;bar"',
                vec[
                    dict['foo' => vec['baz'], 'bar' => vec['123']],
                    dict['boo' => vec['']],
                    dict['test' => vec['123']],
                    dict['foobar' => vec['foo;bar']],
                ],
            ),
            tuple(
                '<http://.../side.jpeg?test=1>; rel="side"; type="image/jpeg",<http://.../side.jpeg?test=2>; rel=side; type="image/jpeg"',
                vec[
                    dict['<http://.../side.jpeg?test=1>' => vec[''], 'rel' => vec['side'], 'type' => vec['image/jpeg']],
                    dict['<http://.../side.jpeg?test=2>' => vec[''], 'rel' => vec['side'], 'type' => vec['image/jpeg']],
                ],
            ),
            tuple(
                '',
                vec[],
            ),
        ];
    }

    <<DataProvider('parseParamsProvider')>>
    public function testParseParams(string $header, vec<dict<string, vec<string>>> $result): void
    {
        Helper::assertSame($result, HM\Header::parse($header));
    }

    public function testParsesArrayHeaders(): void
    {
        $header = vec['a, b', 'c', 'd, e'];
        Helper::assertSame(vec['a', 'b', 'c', 'd', 'e'], HM\Header::normalize($header));
    }
}

namespace HackHttp\Message;

use namespace HH\Lib\Str;
use namespace HH\Lib\Vec;
use namespace HH\Lib\Dict;
use namespace HH;

final class Header
{
    /**
     * Parse an array of header values containing ";" separated data into an
     * array of associative arrays representing the header key value pair data
     * of the header. When a parameter does not contain a value, but just
     * contains a key, this function will inject a key with a '' string value.
     *
     * @param mixed $header Header to parse into components.
     * @return vec<dict<string, vec<string>>>
     */
    public static function parse(mixed $header): vec<dict<string, vec<string>>>
    {
        $trimmed = "\"'  \n\t\r";
        $params = vec<dict<string, vec<string>>>[];
        $matches = vec<string>[];

        foreach (self::normalize($header) as $val) {
            $part = dict<string, vec<string>>[];
            foreach (\preg_split('/;(?=([^"]*"[^"]*")*[^"]*$)/', $val) as $kvp) {
                if (\preg_match_all_with_matches('/<[^>]+>|[^=]+/', $kvp, inout $matches)) {
                    $m = $matches[0];
                    $header_name = \trim($m[0], $trimmed);
                    $header_value = \isset($m[1]) ? \trim($m[1], $trimmed) : '';

                    if (\isset($part[$header_name])) {
                        $part[$header_name][] = $header_value;
                    } else {
                        $part[$header_name] = vec[$header_value];
                    }
                }
            }
            if ($part) {
                $params[] = $part;
            }
        }

        return $params;
    }

    /**
     * Converts an array of header values that may contain comma separated
     * headers into an array of headers with no comma separated values.
     *
     * @param mixed $header Header to normalize.
     * @return vec<string>
     */
    public static function normalize(mixed $header): vec<string>
    {
        if ($header is string) {
            $trim_cb = (string $v): string ==> Str\trim($v);
            return Vec\map(Str\split($header, ","), $trim_cb);
        }

        $result = vec<string>[];
        if($header is vec<_>) {
            foreach ($header as $value) {

                if(!HH\is_any_array($value)) {
                    $value = vec[$value];
                }
                
                foreach ($value as $v) {
                    if($v is string) {
                        if (Str\search($v, ',') is null) {
                            $result[] = $v;
                            continue;
                        }
                        foreach (\preg_split('/,(?=([^"]*"[^"]*")*[^"]*$)/', $v) as $vv) {
                            $result[] = \trim($vv);
                        }
                    }
                }
            }
        }

        return $result;
    }
}

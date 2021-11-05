namespace HackHttp\Message;

use namespace HH;

final class Query
{
    /**
     * Parse a query string into a dict.
     *
     * If multiple values are found for the same key, the value of that key
     * value pair will become a vec<string>. 
     *
     * @param string   $str         Query string to parse
     * @param mixed $urlEncoding How the query string is encoded
     */
    public static function parse(string $str, mixed $urlEncoding = true): dict<arraykey, mixed>
    {
        $result = dict[];

        if ($str === '') {
            return $result;
        }

        $decoder = null;
        
        if ($urlEncoding === true) {
            $decoder =  (string $value): string ==> \rawurldecode(\str_replace('+', ' ', $value));
        } elseif ($urlEncoding === \PHP_QUERY_RFC3986) {
            $decoder = (string $value): string ==> \rawurldecode($value);
        } elseif ($urlEncoding === \PHP_QUERY_RFC1738) {
            $decoder = (string $value): string ==> \urldecode($value);
        } else {
            $decoder = (string $value): string ==> $value;
        }

        foreach (\explode('&', $str) as $kvp) {
            $parts = \explode('=', $kvp, 2);
            $key = $decoder($parts[0]);
            $value = \isset($parts[1]) ? $decoder($parts[1]) : null;
            if (!\isset($result[$key])) {
                $result[$key] = $value;
            } else {
                $result_key = $result[$key];
                if (!($result_key is vec<_>)) {
                    $result[$key] = vec[$result[$key]];
                }
                $result_key = HH\idx($result, $key);
                if($result_key is vec<_>) {
                    $result_key[] = $value;
                    $result[$key] = $result_key;
                }
            }
        }

        return $result;
    }

    /**
     * Build a query string from a dict of key value pairs.
     *
     * @param dict<arraykey, mixed>     $params   Query string parameters.
     * @param int|bool $encoding Set to false to not encode, PHP_QUERY_RFC3986
     *                            to encode using RFC3986, or PHP_QUERY_RFC1738
     *                            to encode using RFC1738.
     */
    public static function build(dict<arraykey, mixed> $params, mixed $encoding = \PHP_QUERY_RFC3986): string
    {
        if (!$params) {
            return '';
        }

        $encoder = null;

        if ($encoding === false) {
            $encoder = (string $str): string ==> $str;
        } elseif ($encoding === \PHP_QUERY_RFC3986) {
            $encoder = (string $str): string ==> \rawurlencode($str); 
        } elseif ($encoding === \PHP_QUERY_RFC1738) {
            $encoder = (string $str): string ==> \urlencode($str);
        } else {
            throw new \InvalidArgumentException('Invalid type');
        }

        $qs = '';
        foreach ($params as $k => $v) {
            $k = $encoder((string) $k);
            if (!($v is vec<_>)) {
                $qs .= $k;
                $v = ($v is bool) ? (int) $v : $v;
                if ($v is  nonnull) {
                    $qs .= '=' . $encoder((string) $v);
                }
                $qs .= '&';
            } else {
                foreach ($v as $vv) {
                    $qs .= $k;
                    $vv = ($vv is bool) ? (int) $vv : $vv;
                    if ($vv is nonnull) {
                        $qs .= '=' . $encoder((string) $vv);
                    }
                    $qs .= '&';
                }
            }
        }

        return $qs ? (string) \substr($qs, 0, -1) : '';
    }
}

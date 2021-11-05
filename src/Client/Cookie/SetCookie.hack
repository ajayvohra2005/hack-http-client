
namespace HackHttp\Client\Cookie;

use HackHttp\Message\Utils;

use namespace HH;
use namespace HH\Lib\Str;
use namespace HH\Lib\Regex;

/**
 * Set-Cookie class
 */
class SetCookie
{
    /**
     * @var dict<arraykey, mixed>
     */
    private static dict<arraykey, mixed> $defaults = dict[
        'Name'     => null,
        'Value'    => null,
        'Domain'   => null,
        'Path'     => '/',
        'Max-Age'  => null,
        'Expires'  => null,
        'Secure'   => false,
        'Discard'  => false,
        'HttpOnly' => false
    ];

    /**
     * @var dict<arraykey, mixed> Cookie data
     */
    private dict<arraykey, mixed> $data;

    /**
     * Create a new SetCookie object from a string.
     *
     * @param dict<arraykey, mixed> $cookie Set-Cookie header
     * @return SetCookie
     */
    public static function fromString(string $cookie): SetCookie
    {
        // Create the default dict
        $data = self::$defaults;
        // Explode the cookie string using a series of semicolons
        $trim_cb = (string $value): string ==> Str\trim($value);

        $pieces = \array_filter(\array_map($trim_cb, \explode(';', $cookie)));
        // The name of the cookie (first kvp) must exist and include an equal sign.
        if (!isset($pieces[0]) || Str\search($pieces[0], '=') is null) {
            return new SetCookie($data);
        }

        // Add the cookie pieces into the parsed data array
        foreach ($pieces as $part) {
            $cookieParts = \explode('=', $part, 2);
            $key = \trim($cookieParts[0]);
            $value = isset($cookieParts[1])
                ? \trim($cookieParts[1], " \n\r\t\0\x0B")
                : true;

            if(Str\lowercase($key) === 'expires' && $value is string) {
                $value =  \strtotime($value);
            } elseif(Str\lowercase($key) === 'max-age' && $value is string) {
                $value = \intval($value);
            }

            // Only check for non-cookies when cookies have been found
            if (!isset($data['Name'])) {
                $data['Name'] = $key;
                $data['Value'] = $value;
            } else {
                $key_found = false;

                foreach (\array_keys(self::$defaults) as $search) {
                    if ($search is string && !\strcasecmp($search, $key)) {
                        $data[$search] = $value;
                        $key_found = true;
                        break;
                    }

                }
                if(!$key_found) {
                    $data[$key] = $value;
                }
            }
        }

        return new SetCookie($data);
    }

    /**
     * @param array $data Array of cookie data provided by a Cookie parser
     */
    public function __construct(dict<arraykey, mixed> $data = dict[])
    {
        /** @var array|null $replaced will be null in case of replace error */
        $replaced = \array_replace(self::$defaults, $data);
        if ($replaced === null) {
            throw new \InvalidArgumentException('Unable to replace the default values for the Cookie.');
        }

        $expires = HH\idx($replaced, 'Expires');
        if($expires is string) {
            $replaced['Expires'] =  \strtotime($expires);
        } 
        
        $max_age = HH\idx($replaced, 'Max-Age');
        if($max_age is string) {
            $replaced['Max-Age'] = \intval($max_age);
        }

        $this->data = $replaced;
        // Extract the Expires value and turn it into a UNIX timestamp if needed
        $max_age = $this->getMaxAge();
        $expires = $this->getExpires();
        if (!$expires && $max_age) {
            // Calculate the Expires date
            $this->setExpires(\time() + $max_age);
        } 
    }

    public function __toString(): string
    {
        $str = $this->getName() . '=' . (string)$this->getValue() . '; ';
        foreach ($this->data as $k => $v) {
            if ($k !== 'Name' && $k !== 'Value' && $v !== null && $v !== false) {
                if ($k === 'Expires') {
                    $str .= 'Expires=' . \gmdate('D, d M Y H:i:s \G\M\T', $this->getExpires()) . '; ';
                } elseif(Utils::is_implicit_string($v)) {
                    $str_v = (string)$v;
                    $str .= ($v === true ? $k : "{$k}={$str_v}") . '; ';
                }
            }
        }

        return \rtrim($str, '; ');
    }

    public function toArray(): dict<arraykey, mixed>
    {
        return $this->data;
    }

    /**
     * Get the cookie name.
     *
     * @return string
     */
    public function getName(): string
    {
        $name = HH\idx($this->data, 'Name');
        return $name is string? $name: '';
    }

    /**
     * Set the cookie name.
     *
     * @param string $name Cookie name
     */
    public function setName(string $name): void
    {
        $this->data['Name'] = $name;
    }

    /**
     * Get the cookie value.
     *
     * @return ?string
     */
    public function getValue(): mixed
    {
        return HH\idx($this->data, 'Value');
    }

    /**
     * Set the cookie value.
     *
     * @param mixed $value Cookie value
     */
    public function setValue(string $value): void
    {
        $this->data['Value'] = $value;
    }

    /**
     * Get the domain.
     *
     * @return string
     */
    public function getDomain(): string
    {
        $domain = HH\idx($this->data, 'Domain');
        return $domain is string? $domain: '';
    }

    /**
     * Set the domain of the cookie.
     *
     * @param string $domain
     */
    public function setDomain(string $domain): void
    {
        $this->data['Domain'] = $domain;
    }

    /**
     * Get the path.
     *
     * @return string
     */
    public function getPath(): string
    {
        $path = HH\idx($this->data, 'Path');
        return $path is string? $path: '';
    }

    /**
     * Set the path of the cookie.
     *
     * @param string $path Path of the cookie
     */
    public function setPath(string $path): void
    {
        $this->data['Path'] = $path;
    }

    /**
     * Maximum lifetime of the cookie in seconds.
     *
     * @return ?int
     */
    public function getMaxAge(): ?int
    {
        $max_age = HH\idx($this->data, 'Max-Age');
        $max_age = $max_age is int ? $max_age : null;
        return $max_age;
    }

    /**
     * Set the max-age of the cookie.
     *
     * @param int $maxAge Max age of the cookie in seconds
     */
    public function setMaxAge(int $maxAge): void
    {
        $this->data['Max-Age'] = $maxAge;
    }

    /**
     * The UNIX timestamp when the cookie Expires.
     *
     * @return ?int
     */
    public function getExpires(): ?int
    {
        $expires = HH\idx($this->data, 'Expires');
        $expires = $expires is int ? $expires : null;
        return $expires;
    }

    /**
     * Set the unix timestamp for which the cookie will expire.
     *
     * @param mixed $timestamp Unix timestamp or any English textual datetime description.
     */
    public function setExpires(mixed $timestamp): void
    {
        if($timestamp is string) {
            $timestamp = \strtotime($timestamp);
        }

        if($timestamp is int) {
            $this->data['Expires']  = $timestamp;
        } 
    }

    /**
     * Get whether or not this is a secure cookie.
     *
     * @return bool|null
     */
    public function getSecure(): ?bool
    {
        $secure = HH\idx($this->data, 'Secure');
        return $secure is bool? $secure: null;
    }

    /**
     * Set whether or not the cookie is secure.
     *
     * @param bool $secure Set to true or false if secure
     */
    public function setSecure(bool $secure): void
    {
        $this->data['Secure'] = $secure;
    }

    /**
     * Get whether or not this is a session cookie.
     *
     * @return ?bool
     */
    public function getDiscard(): ?bool
    {
        $discard = HH\idx($this->data, 'Discard');
        return $discard is bool? $discard: null;
    }

    /**
     * Set whether or not this is a session cookie.
     *
     * @param bool $discard Set to true or false if this is a session cookie
     */
    public function setDiscard(bool $discard): void
    {
        $this->data['Discard'] = $discard;
    }

    /**
     * Get whether or not this is an HTTP only cookie.
     *
     * @return ?bool
     */
    public function getHttpOnly(): ?bool
    {
        $http_only = HH\idx($this->data, 'HttpOnly');
        return $http_only is bool? $http_only: null;
    }

    /**
     * Set whether or not this is an HTTP only cookie.
     *
     * @param bool $httpOnly Set to true or false if this is HTTP only
     */
    public function setHttpOnly(bool $httpOnly): void
    {
        $this->data['HttpOnly'] = $httpOnly;
    }

    /**
     * Check if the cookie matches a path value.
     *
     * A request-path path-matches a given cookie-path if at least one of
     * the following conditions holds:
     *
     * - The cookie-path and the request-path are identical.
     * - The cookie-path is a prefix of the request-path, and the last
     *   character of the cookie-path is %x2F ("/").
     * - The cookie-path is a prefix of the request-path, and the first
     *   character of the request-path that is not included in the cookie-
     *   path is a %x2F ("/") character.
     *
     * @param string $requestPath Path to check against
     * @return bool True if matches path
     */
    public function matchesPath(string $requestPath): bool
    {
        $cookiePath = $this->getPath();

        if(!$cookiePath) {
            return true;
        }

        // Match on exact matches or when path is the default empty "/"
        if ($cookiePath === '/' || $cookiePath == $requestPath) {
            return true;
        }

        // Ensure that the cookie-path is a prefix of the request path.
        if (0 !== Str\search($requestPath, $cookiePath)) {
            return false;
        }

        // Match if the last character of the cookie-path is "/"
        if (Str\slice($cookiePath, -1, 1) === '/') {
            return true;
        }

        // Match if the first character not included in cookie path is "/"
        return Str\slice($requestPath, \strlen($cookiePath), 1) === '/';
    }

    /**
     * Check if the cookie matches a domain value.
     *
     * @param string $domain Domain to check against
     */
    public function matchesDomain(string $domain): bool
    {
        $cookieDomain = $this->getDomain();
        if (!$cookieDomain) {
            return true;
        }

        // Remove the leading '.' as per spec in RFC 6265.
        // https://tools.ietf.org/html/rfc6265#section-5.2.3
        $cookieDomain = \ltrim($cookieDomain, '.');

        // Domain not set or exact match.
        if (!$cookieDomain || !\strcasecmp($domain, $cookieDomain)) {
            return true;
        }

        // Matching the subdomain according to RFC 6265.
        // https://tools.ietf.org/html/rfc6265#section-5.1.3
        if (\filter_var($domain, \FILTER_VALIDATE_IP)) {
            return false;
        }

        return (bool) \preg_match('/\.' . \preg_quote($cookieDomain, '/') . '$/', $domain);
    }

    /**
     * Check if the cookie is expired.
     */
    public function isExpired(): bool
    {
        $expires = $this->getExpires();
        return $expires is int && \time() > $expires;
    }

    /**
     * Check if the cookie is valid according to RFC 6265.
     *
     * @return mixed Returns true if valid or an error message if invalid
     */
    public function validate(): mixed
    {
        $name = $this->getName();
        if (Str\is_empty($name)) {
            return 'The cookie name must not be empty';
        }

        // Check if any of the invalid characters are present in the cookie name
        if (\preg_match('/[\x00-\x20\x22\x28-\x29\x2c\x2f\x3a-\x40\x5c\x7b\x7d\x7f]/',$name)) {
            return 'Cookie name must not contain invalid characters: ASCII '
                . 'Control characters (0-31;127), space, tab and the '
                . 'following characters: ()<>@,;:\"/?={}';
        }

        // Empty strings are technically against RFC 6265.
        $value = $this->getValue();
        if ($value is null) {
            return 'The cookie value must not be empty';
        }

        // Domains must not be empty.
        $domain = $this->getDomain();
        if ($domain is null || Str\is_empty($domain)) {
            return 'The cookie domain must not be empty';
        }

        return true;
    }
}

namespace HackHttp\Message;

use namespace HH\Lib\IO;
use namespace HH\Lib\File;
use namespace HH\Lib\Dict;
use namespace HH\Lib\Str;
use namespace HH;

use type HackHttp\Message\{StreamInterface};


type StreamOptions  = shape('size' => ?int, 'metadata' => ?dict<string, mixed>);


/**
 * Hack stream implementation.
 */
class Stream implements StreamInterface
{
    const READABLE_MODES = '/r|a\+|ab\+|w\+|wb\+|x\+|xb\+|c\+|cb\+/';
    const WRITABLE_MODES = '/a|w|r\+|rb\+|rw|x|c/';

    /** @var IO\Handle */
    private ?IO\Handle $handle;

    /** @var int|null */
    private ?int $size;

    /** @var bool */
    private bool $seekable = false;

    /** @var bool */
    private bool $readable = false;

    /** @var bool */
    private bool $writable = false;

    /** @var string|null */
    private ?string $uri;

    /** @var dict<string, mixed> */
    private dict<string, mixed> $metadata=dict[];

    /**
     * This constructor accepts an associative array of options.
     *
     * - size: (int) If a read stream would otherwise have an indeterminate
     *   size, but the size is known due to foreknowledge, then you can
     *   provide that size, in bytes.
     * - metadata: dict<string, mixed> Metadata of the stream, with 'mode', 'seekable', 'uri'
     *                            
     *
     * @param Handle $handle  Stream resource to wrap.
     * @param ?StreamOptions $options Stream options.
     *
     * @throws \InvalidArgumentException if the stream is not a stream resource
     */
    public function __construct(IO\Handle $handle, ?StreamOptions $options=null )
    {
        if (! ($handle is IO\Handle)) {
            throw new \InvalidArgumentException('Stream must be a HH\Lib\IO\Handle');
        }

        $this->handle = $handle;

        if ($options is nonnull && \isset($options['size'])) {
            $this->size = $options['size'];
        }

        if($options is nonnull && \isset($options['metadata'])) {
            $m = $options['metadata'];
            if($m is nonnull) {
                $this->metadata = $m;
            }
        }
        
        if($this->metadata is dict<_,_>) {

            $value = HH\idx($this->metadata, 'seekable');
            if($value is bool) {
                $this->seekable = $value;
            } 

            $value = HH\idx($this->metadata, 'mode');
            if($value is string) {
                $this->readable = (bool)\preg_match(self::READABLE_MODES, $value );
                $this->writable = (bool)\preg_match(self::WRITABLE_MODES, $value );
            }

            $value = HH\idx($this->metadata, 'uri');
            if($value is string) {
                $this->uri = $value;
            }
        }

        if($handle is nonnull) {
            $this->setMetadataFromHandle($handle);
        }
    }

    public function __toString(): string
    {
        if ($this->isSeekable()) {
            $this->seek(0);
        }
        return $this->getContents();
    }

    public function getContents(): string
    {
        if ($this->handle is null) {
            throw new \RuntimeException('Stream is detached');
        }

        return $this->read(null);
    }

    public function close(): void
    {
        if ($this->handle is nonnull) {
            if ($this->handle is IO\CloseableHandle) {
                $this->handle->close();
            }
            $this->detach();
        }
    }

    public function detach(): void
    {
        $this->size = null;
        $this->uri = null;
        $this->readable = false;
        $this->writable = false;
        $this->seekable = false;
        $this->handle = null;
    }

    public function getSize(): ?int
    {
        if ($this->size is nonnull) {
            return $this->size;
        }

        if ($this->handle is null) {
            return null;
        }

        if($this->handle is File\Handle) {
            return $this->handle->getSize();
        }

        return null;
    }

    public function isReadable(): bool
    {
        return $this->readable;
    }

    public function isWritable(): bool
    {
        return $this->writable;
    }

    public function isSeekable(): bool
    {
        return $this->seekable;
    }

    public function eof(): bool
    {
        if ($this->handle is null) {
            throw new \RuntimeException('Stream is detached');
        }

        $retval = false;

        try {
            $retval = $this->tell() === $this->getSize();
        } catch(\Exception $e) {

        }
       return $retval;
    }


    public function tell(): int
    {
        if ($this->handle is null) {
            throw new \RuntimeException('Stream is detached');
        }

        if (!$this->seekable) {
            throw new \RuntimeException('Stream is not seekable');
        }

        $result = null;
        if ($this->handle is IO\SeekableHandle) {
            $result = $this->handle->tell();
        } else {
             throw new \RuntimeException('Stream is not IO\SeekableHandle');
        }

        if ($result is null) {
            throw new \RuntimeException('Unable to determine stream position');
        }

        return $result;
    }

    public function rewind(): void
    {
        $this->seek(0);
    }

    public function seek(int $offset, int $whence = \SEEK_SET): void
    {
        $whence = (int) $whence;

        if ($this->handle is null) {
            throw new \RuntimeException('Stream is detached');
        }

        if (!$this->seekable) {
            throw new \RuntimeException('Stream is not seekable');
        }

        if ($this->handle is IO\SeekableHandle) {

            if($whence == \SEEK_CUR) {
                $offset += $this->handle->tell();
            } elseif ($whence == \SEEK_END) {
                $cur_size = $this->getSize();
                if($cur_size) {
                    $offset += $cur_size;
                }
            }

            if ($this->handle is IO\SeekableHandle) {
                $this->handle->seek($offset);
            }

            if($this->tell() != $offset) {
                throw new \RuntimeException('Unable to seek to stream position '
                . $offset . ' with whence ' . \var_export($whence, true));
            }

        } else {
            throw new \RuntimeException('Seekable is not a IO\SeekableHandle');
        }
    }

    public function read(?int $length): string
    {
        if ($this->handle is null) {
            throw new \RuntimeException('Stream is detached');
        }

        if (!$this->readable) {
            throw new \RuntimeException('Cannot read from non-readable stream');
        }

        if ($length is nonnull && $length < 0) {
            throw new \RuntimeException('Length parameter cannot be negative');
        }

        if (0 === $length) {
            return '';
        }

        $string = null;
        if ($this->handle is IO\ReadHandle) {
            $string = \HH\Asio\join($this->handle->readAllAsync($length));
        } else {
            throw new \RuntimeException('Readable is not a IO\ReadHandle');
        }

        if ($string is null) {
            throw new \RuntimeException('Unable to read from stream');
        }

        return $string;
    }

    public function write(string $string): int
    {
        if ($this->handle is null) {
            throw new \RuntimeException('Stream is detached');
        }

        if (!$this->writable) {
            throw new \RuntimeException('Cannot wrtie to non-writeable stream');
        }

        if ($this->handle is IO\WriteHandle) {
            \HH\Asio\join($this->handle->writeAllAsync($string));
        } else {
            throw new \RuntimeException('Writeable stream is not a IO\WriteHandle');
        }

        return Str\length($string);
    }

    /**
     * {@inheritdoc}
     *
     * @return string|dict<string, mixed>|null
     */
    public function getMetadata(?string $key = null): mixed
    {
         if ($this->handle is nonnull) {
            if ($key is null) {
                return $this->metadata;
            } else {
                return HH\idx($this->metadata, $key);
            }
        } 
        
        return null;
        
    }

    private function setMetadataFromHandle(IO\Handle $handle): void
    {

        if($handle is IO\ReadHandle) {
            $this->readable = true;
        } 

        if($handle is IO\WriteHandle) {
            $this->writable = true;
        }

        if($handle is IO\SeekableHandle) {
            $this->seekable = true;
        }

        if($handle is File\Handle) {
            $file_path = \realpath($handle->getPath());
            $this->uri = "file://{$file_path}";
            $this->metadata['uri'] = $this->uri;
        }

    }
}

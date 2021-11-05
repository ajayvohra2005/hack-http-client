namespace HackHttp\Message;

type PumpFunction = (function(?int): ?string);

/**
 * Provides a read only stream that pumps data from a PumpFunction.
 *
 * When invoking the provided PumpFunction, the PumpStream will pass the amount of
 * data requested to read to the PumpFunction. The PumpFunction can choose to ignore
 * this value and return fewer or more bytes than requested. Any extra data
 * returned by the provided PumpFunction is buffered internally until drained using
 * the read() function of the PumpStream. The provided PumpFunction MUST return
 * null when there is no more data to read.
 */
final class PumpStream implements StreamInterface
{
    /** @var PumpFunction */
    private ?PumpFunction $source;

    /** @var int|null */
    private ?int $size;

    /** @var int */
    private int $tellPos = 0;

    /** @var dict<string, mixed> */
    private ?dict<string, mixed> $metadata;

    /** @var string */
    private ?BufferStream $buffer;

    /**
     * @param PumpFunction  $source  Source of the stream data. The callable MAY
     *                               accept an integer argument used to control the
     *                               amount of data to return. The callable MUST
     *                               return a string when called, or null on error.
     * @param StreamOptions $options Stream options:
     *                                   - metadata: Hash of metadata to use with stream.
     *                                   - size: Size of the stream, if known.
     */
    public function __construct(PumpFunction $source, ?StreamOptions $options = null)
    {
        $this->source = $source;

        if($options is nonnull) { 
            if(\isset($options['size'])) {
                $this->size = $options['size'];
            }
            if(\isset($options['metadata'])) {
                $this->metadata = $options['metadata'];
            }
        }
        $this->buffer = new BufferStream();
    }
    
    public function __toString(): string
    {
        try {
            return Utils::copyToString($this);
        } catch (\Exception $e) {
           throw new \RuntimeException("Cannot copy to string");
        }
    }

    public function close(): void
    {
        $this->detach();
    }

    public function detach(): void
    {
        $this->tellPos = 0;
        $this->source = null;
        $this->buffer = null;
    }

    public function getSize(): ?int
    {
        return $this->size;
    }

    public function tell(): int
    {
        return $this->tellPos;
    }

    public function eof(): bool
    {
        return $this->source === null;
    }

    public function isSeekable(): bool
    {
        return false;
    }

    public function rewind(): void
    {
        throw new \RuntimeException('Cannot rewind a PumpStream');
    }

    public function seek(int $offset, int $whence = \SEEK_SET): void
    {
        throw new \RuntimeException('Cannot seek a PumpStream');
    }

    public function isWritable(): bool
    {
        return false;
    }

    public function write(string $string): int
    {
        throw new \RuntimeException('Cannot write to a PumpStream');
    }

    public function isReadable(): bool
    {
        return true;
    }

    public function read(?int $length): string
    {
        if($this->buffer is null) {
            return '';
        }
        
        if($length is int) {
            $data = $this->buffer->read($length);
            $readLen = \strlen($data);
            $this->tellPos += $readLen;
            $remaining = $length - $readLen;

            if ($remaining > 0) {
                $this->pump($remaining);
                if($this->buffer is nonnull) {
                    $data .= $this->buffer->read($remaining);
                    $this->tellPos += \strlen($data) - $readLen;
                }
            }

            return $data;
        } else {
            return $this->getContents();
        }
    }

    public function getContents(): string
    {
        $result = '';

        if($this->source is nonnull) {
            while (!$this->eof()) {
                $value = $this->read(1000000);
                if($value is string) {
                    $result .= $value;
                } else {
                    break;
                }
            }
        }

        return $result;
    }

    /**
     * {@inheritdoc}
     *
     * @return mixed
     */
    public function getMetadata(?string $key = null): mixed
    {
        if (!$key) {
            return $this->metadata;
        }

        return $this->metadata[$key] ?? null;
    }

    private function pump(int $length): void
    {
        
        do {
            $f = $this->source;
            if($f is nonnull) {
                $data = $f($length);
                if ($data is null) {
                    $this->source = null;
                    return;
                }
                if($this->buffer is nonnull) {
                    $this->buffer->write($data);
                    $length -= \strlen($data);
                }
            }
        } while ($f is nonnull && $length > 0);
    }
}

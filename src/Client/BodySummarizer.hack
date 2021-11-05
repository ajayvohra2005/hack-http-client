
namespace HackHttp\Client;

use type HackHttp\Message\{MessageInterface, Message};

final class BodySummarizer implements BodySummarizerInterface
{
    /**
     * @var ?int
     */
    private ?int $truncateAt;

    public function __construct(?int $truncateAt = null)
    {
        $this->truncateAt = $truncateAt;
    }

    /**
     * Returns a summarized message body.
     */
    public function summarize(MessageInterface $message): ?string
    {
        return $this->truncateAt === null
            ? Message::bodySummary($message)
            : Message::bodySummary($message, $this->truncateAt);
    }
}

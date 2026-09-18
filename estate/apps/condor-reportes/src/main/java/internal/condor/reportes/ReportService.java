package internal.condor.reportes;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.Map;

public final class ReportService {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private ReportService() {
    }

    public static String currentReportJson() {
        try {
            return MAPPER.writeValueAsString(Map.of(
                    "generated_at", Instant.now().toString(),
                    "status", "ok"));
        } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
            throw new RuntimeException(e);
        }
    }
}

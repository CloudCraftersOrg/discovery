package internal.condor.reportes;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Path;
import org.junit.jupiter.api.Test;

class ReportServiceTest {

    @Test
    void reportContainsStatus() {
        assertTrue(ReportService.currentReportJson().contains("\"status\":\"ok\""));
    }

    @Test
    void buildIsNotForcedToFail() {
        assertFalse(Path.of("FAIL_BUILD").toFile().exists());
    }
}

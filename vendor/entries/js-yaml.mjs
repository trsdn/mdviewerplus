// Build-time entry for the Full-edition YAML frontmatter module.
// Only the failsafe-schema loading surface is re-exported; dumping, custom
// schemas, and type construction are intentionally not exposed to the preview.
import { load, FAILSAFE_SCHEMA, YAMLException } from "js-yaml";

export { load, FAILSAFE_SCHEMA, YAMLException };

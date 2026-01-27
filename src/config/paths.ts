import fs from "node:fs";
import path from "node:path";

import { env } from "./env.js";

export const uploadsDir = path.isAbsolute(env.UPLOAD_DIR)
  ? env.UPLOAD_DIR
  : path.join(process.cwd(), env.UPLOAD_DIR);

export const ensureUploadsDir = () => {
  fs.mkdirSync(uploadsDir, { recursive: true });
  return uploadsDir;
};

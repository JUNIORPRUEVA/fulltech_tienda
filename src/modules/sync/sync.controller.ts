import type { RequestHandler } from "express";

import { syncService } from "./sync.service.js";
import type { BaseOp } from "./sync.schemas.js";

export const push: RequestHandler = async (req, res, next) => {
  try {
    const ops = req.body as BaseOp[];
    const userId = req.user!.id;

    const results = await syncService.pushBatch({ userId, ops });

    res.status(200).json({ results });
  } catch (e) {
    next(e);
  }
};

export const pull: RequestHandler = async (req, res, next) => {
  try {
    const { since } = req.query as { since: string };
    const userId = req.user!.id;

    const sinceDate = new Date(since);
    const response = await syncService.pull({ userId, since: sinceDate });

    res.status(200).json(response);
  } catch (e) {
    next(e);
  }
};

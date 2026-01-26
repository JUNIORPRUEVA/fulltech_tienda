import type { RequestHandler } from "express";

import { salesService } from "./sales.service.js";

export const listSales: RequestHandler = async (req, res, next) => {
  try {
    const { limit, offset } = req.query as unknown as {
      limit: number;
      offset: number;
    };
    const ownerId = req.user!.id;

    const { data, total } = await salesService.list({ ownerId, limit, offset });

    res.status(200).json({
      data,
      pagination: { limit, offset, total },
    });
  } catch (e) {
    next(e);
  }
};

export const getSale: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const id = String(req.params.id);
    const sale = await salesService.getById({ ownerId, id });
    res.status(200).json({ data: sale });
  } catch (e) {
    next(e);
  }
};

export const createSale: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;

    const sale = await salesService.create({
      ownerId,
      userId,
      deviceId: req.deviceId,
      data: req.body,
    });

    res.status(201).json({ data: sale });
  } catch (e) {
    next(e);
  }
};

export const updateSale: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;
    const id = String(req.params.id);

    const sale = await salesService.update({
      ownerId,
      userId,
      deviceId: req.deviceId,
      id,
      data: req.body,
    });

    res.status(200).json({ data: sale });
  } catch (e) {
    next(e);
  }
};

export const deleteSale: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;
    const id = String(req.params.id);

    const sale = await salesService.softDelete({
      ownerId,
      userId,
      deviceId: req.deviceId,
      id,
    });

    res.status(200).json({ data: sale });
  } catch (e) {
    next(e);
  }
};

import type { RequestHandler } from "express";

import { productsService } from "./products.service.js";

export const listProducts: RequestHandler = async (req, res, next) => {
  try {
    const { limit, offset } = req.query as unknown as {
      limit: number;
      offset: number;
    };
    const ownerId = req.user!.id;

    const { data, total } = await productsService.list({ ownerId, limit, offset });

    res.status(200).json({
      data,
      pagination: { limit, offset, total },
    });
  } catch (e) {
    next(e);
  }
};

export const getProduct: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const id = String(req.params.id);
    const product = await productsService.getById({ ownerId, id });
    res.status(200).json({ data: product });
  } catch (e) {
    next(e);
  }
};

export const createProduct: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;

    const product = await productsService.create({
      ownerId,
      userId,
      deviceId: req.deviceId,
      data: req.body,
    });

    res.status(201).json({ data: product });
  } catch (e) {
    next(e);
  }
};

export const updateProduct: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;
    const id = String(req.params.id);

    const product = await productsService.update({
      ownerId,
      userId,
      deviceId: req.deviceId,
      id,
      data: req.body,
    });

    res.status(200).json({ data: product });
  } catch (e) {
    next(e);
  }
};

export const deleteProduct: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;
    const id = String(req.params.id);

    const product = await productsService.softDelete({
      ownerId,
      userId,
      deviceId: req.deviceId,
      id,
    });

    res.status(200).json({ data: product });
  } catch (e) {
    next(e);
  }
};

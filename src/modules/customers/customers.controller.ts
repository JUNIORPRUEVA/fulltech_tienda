import type { RequestHandler } from "express";

import { customersService } from "./customers.service.js";

export const listCustomers: RequestHandler = async (req, res, next) => {
  try {
    const { limit, offset } = req.query as unknown as {
      limit: number;
      offset: number;
    };
    const ownerId = req.user!.id;

    const { data, total } = await customersService.list({ ownerId, limit, offset });

    res.status(200).json({
      data,
      pagination: { limit, offset, total },
    });
  } catch (e) {
    next(e);
  }
};

export const getCustomer: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const id = String(req.params.id);
    const customer = await customersService.getById({ ownerId, id });
    res.status(200).json({ data: customer });
  } catch (e) {
    next(e);
  }
};

export const createCustomer: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;

    const customer = await customersService.create({
      ownerId,
      userId,
      deviceId: req.deviceId,
      data: req.body,
    });

    res.status(201).json({ data: customer });
  } catch (e) {
    next(e);
  }
};

export const updateCustomer: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;
    const id = String(req.params.id);

    const customer = await customersService.update({
      ownerId,
      userId,
      deviceId: req.deviceId,
      id,
      data: req.body,
    });

    res.status(200).json({ data: customer });
  } catch (e) {
    next(e);
  }
};

export const deleteCustomer: RequestHandler = async (req, res, next) => {
  try {
    const ownerId = req.user!.id;
    const userId = req.user!.id;
    const id = String(req.params.id);

    const customer = await customersService.softDelete({
      ownerId,
      userId,
      deviceId: req.deviceId,
      id,
    });

    res.status(200).json({ data: customer });
  } catch (e) {
    next(e);
  }
};

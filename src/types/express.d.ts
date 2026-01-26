import "express";

declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
      };
      deviceId?: string;
      id?: string;
    }
  }
}

export {};

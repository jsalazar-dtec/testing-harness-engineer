import { randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';

export interface UserRecord {
  id: string;
  email: string;
  passwordHash: string;
  createdAt: Date;
}

// Domain error thrown by the service when a second registration collides
// with an email that is already taken. The controller (T3) is responsible
// for mapping it to HTTP 409 with body { error: "email_ya_registrado" }.
// Keeping the error as a class (not a status code) preserves service
// portability outside HTTP.
export class EmailAlreadyRegisteredError extends Error {
  constructor(email: string) {
    super(`email already registered: ${email}`);
    this.name = 'EmailAlreadyRegisteredError';
  }
}

// bcrypt cost is fixed to 10 by contract (spec says cost >= 10). Making it
// configurable would let a caller lower it below the contract's floor.
const BCRYPT_COST = 10;

// Email is normalized to lower-case at the storage boundary — never
// mutated on the returned record, so the caller sees what they passed in.
// This is the smallest thing that lets Ana@X.COM and ana@x.com resolve
// to the same user without leaking the normalization into responses.
const normalize = (email: string): string => email.toLowerCase();

@Injectable()
export class UsersService {
  private readonly storage = new Map<string, UserRecord>();

  async create(email: string, password: string): Promise<UserRecord> {
    const key = normalize(email);
    if (this.storage.has(key)) {
      throw new EmailAlreadyRegisteredError(email);
    }
    const passwordHash = await bcrypt.hash(password, BCRYPT_COST);
    const record: UserRecord = {
      id: randomUUID(),
      email,
      passwordHash,
      createdAt: new Date(),
    };
    this.storage.set(key, record);
    return record;
  }

  findByEmail(email: string): UserRecord | undefined {
    return this.storage.get(normalize(email));
  }
}

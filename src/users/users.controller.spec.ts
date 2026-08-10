// Unit tests for UsersController — the mapping and the exception handling
// in isolation. The full HTTP shape (ValidationPipe wiring, actual 400
// body) is validated by the e2e test in test/users.e2e-spec.ts.
import { ConflictException } from '@nestjs/common';
import {
  EmailAlreadyRegisteredError,
  UserRecord,
  UsersService,
} from './users.service';
import { UsersController } from './users.controller';

const anyUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const buildRecord = (overrides: Partial<UserRecord> = {}): UserRecord => ({
  id: anyUuid,
  email: 'ana@x.com',
  passwordHash: '$2b$10$hash',
  createdAt: new Date('2026-08-10T00:00:00Z'),
  ...overrides,
});

describe('UsersController', () => {
  let service: jest.Mocked<Pick<UsersService, 'create' | 'findByEmail'>>;
  let controller: UsersController;

  beforeEach(() => {
    service = {
      create: jest.fn(),
      findByEmail: jest.fn(),
    };
    controller = new UsersController(service as unknown as UsersService);
  });

  it('returns only id and email on success — never passwordHash or createdAt', async () => {
    service.create.mockResolvedValue(buildRecord());
    const response = await controller.create({
      email: 'ana@x.com',
      password: 'Segur0!Passw0rd',
    });
    expect(response).toEqual({ id: anyUuid, email: 'ana@x.com' });
    expect(Object.keys(response)).toEqual(['id', 'email']);
  });

  it('maps EmailAlreadyRegisteredError to 409 with body { error: email_ya_registrado }', async () => {
    service.create.mockRejectedValue(
      new EmailAlreadyRegisteredError('ana@x.com'),
    );
    await expect(
      controller.create({ email: 'ana@x.com', password: 'Segur0!Passw0rd' }),
    ).rejects.toBeInstanceOf(ConflictException);
    try {
      await controller.create({
        email: 'ana@x.com',
        password: 'Segur0!Passw0rd',
      });
    } catch (err) {
      const body = (err as ConflictException).getResponse();
      expect(body).toEqual({ error: 'email_ya_registrado' });
    }
  });

  it('does not forward the incoming email in the conflict body', async () => {
    service.create.mockRejectedValue(
      new EmailAlreadyRegisteredError('leaky@x.com'),
    );
    try {
      await controller.create({
        email: 'leaky@x.com',
        password: 'Segur0!Passw0rd',
      });
    } catch (err) {
      const body = JSON.stringify((err as ConflictException).getResponse());
      expect(body).not.toContain('leaky@x.com');
    }
  });

  it('re-throws unknown errors untouched (does not swallow bugs)', async () => {
    service.create.mockRejectedValue(new Error('unexpected'));
    await expect(
      controller.create({ email: 'ana@x.com', password: 'Segur0!Passw0rd' }),
    ).rejects.toThrow('unexpected');
  });
});

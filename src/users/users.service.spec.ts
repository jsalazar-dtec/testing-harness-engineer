// Unit tests for UsersService. No controller, no pipe, no HTTP: just the
// service in isolation. If persistence, hashing or duplicate detection
// break here, no upper layer saves them — T3 relies on this contract.
import * as bcrypt from 'bcryptjs';
import { EmailAlreadyRegisteredError, UsersService } from './users.service';

const UUID_V4_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

describe('UsersService', () => {
  let service: UsersService;

  beforeEach(() => {
    service = new UsersService();
  });

  it('creates a user and returns a record with a uuid v4 id', async () => {
    const record = await service.create('ana@x.com', 'Segur0!Passw0rd');
    expect(record.id).toMatch(UUID_V4_RE);
    expect(record.email).toBe('ana@x.com');
    expect(record.createdAt).toBeInstanceOf(Date);
  });

  it('hashes the password with bcrypt (cost >= 10) and never stores it in clear', async () => {
    const password = 'Segur0!Passw0rd';
    const record = await service.create('ana@x.com', password);
    expect(record.passwordHash).not.toBe(password);
    expect(record.passwordHash).toMatch(/^\$2[aby]\$1[0-9]\$/);
    expect(await bcrypt.compare(password, record.passwordHash)).toBe(true);
  });

  it('does not expose the plain password anywhere in the persisted record', async () => {
    const password = 'Segur0!Passw0rd';
    const record = await service.create('ana@x.com', password);
    expect(JSON.stringify(record)).not.toContain(password);
  });

  it('rejects a second registration with the same email', async () => {
    await service.create('ana@x.com', 'Segur0!Passw0rd');
    await expect(
      service.create('ana@x.com', 'AnotherPass1!'),
    ).rejects.toBeInstanceOf(EmailAlreadyRegisteredError);
  });

  it('keeps the first user unchanged when a duplicate registration is rejected', async () => {
    const first = await service.create('ana@x.com', 'Segur0!Passw0rd');
    await service.create('ana@x.com', 'AnotherPass1!').catch(() => undefined);
    const found = service.findByEmail('ana@x.com');
    expect(found).toBeDefined();
    expect(found?.id).toBe(first.id);
  });

  it('treats email as case-insensitive when detecting duplicates', async () => {
    await service.create('Ana@X.COM', 'Segur0!Passw0rd');
    await expect(
      service.create('ana@x.com', 'AnotherPass1!'),
    ).rejects.toBeInstanceOf(EmailAlreadyRegisteredError);
  });

  it('findByEmail returns the persisted record', async () => {
    const created = await service.create('ana@x.com', 'Segur0!Passw0rd');
    expect(service.findByEmail('ana@x.com')?.id).toBe(created.id);
  });

  it('findByEmail is case-insensitive', async () => {
    await service.create('ana@x.com', 'Segur0!Passw0rd');
    expect(service.findByEmail('ANA@X.COM')).toBeDefined();
  });

  it('findByEmail returns undefined for an unknown email', () => {
    expect(service.findByEmail('nadie@x.com')).toBeUndefined();
  });

  it('generates a distinct uuid for each user', async () => {
    const a = await service.create('ana@x.com', 'Segur0!Passw0rd');
    const b = await service.create('juan@x.com', 'Otr4Pass!word');
    expect(a.id).not.toBe(b.id);
  });
});

// End-to-end tests for POST /users. Goes through the real ValidationPipe
// + custom exceptionFactory wired in main.ts, so it asserts the actual
// response body — the shape the client will see. This is exactly the
// contract that T1's unit tests do not cover (they only check that a
// constraint fires on the right property; not that the body says
// "password_debil").
import {
  BadRequestException,
  INestApplication,
  ValidationPipe,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { ValidationError } from 'class-validator';
import request from 'supertest';
import { AppModule } from '../src/app.module';

const VALID = { email: 'ana@x.com', password: 'Segur0!Passw0rd' } as const;

describe('POST /users (e2e)', () => {
  let app: INestApplication;

  beforeEach(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    // Same wiring as main.ts. The e2e test builds its own app, so it
    // has to mirror the global pipe or it would validate against the
    // default ValidationPipe and miss the "error: <code>" contract.
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
        exceptionFactory: (errors: ValidationError[]) => {
          const first = errors[0];
          const firstMessage =
            Object.values(first?.constraints ?? {})[0] ?? 'invalid_payload';
          return new BadRequestException({ error: firstMessage });
        },
      }),
    );
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('201 with only id and email — never password or passwordHash', async () => {
    const res = await request(app.getHttpServer()).post('/users').send(VALID);
    expect(res.status).toBe(201);
    const expected: Record<string, unknown> = {
      id: expect.stringMatching(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
      ) as unknown,
      email: 'ana@x.com',
    };
    expect(res.body).toEqual(expected);
    expect(JSON.stringify(res.body)).not.toContain('password');
    expect(JSON.stringify(res.body)).not.toContain('hash');
  });

  it('409 with { error: "email_ya_registrado" } on duplicate', async () => {
    await request(app.getHttpServer()).post('/users').send(VALID).expect(201);
    const res = await request(app.getHttpServer()).post('/users').send(VALID);
    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: 'email_ya_registrado' });
  });

  it('the 409 body never contains the incoming email', async () => {
    const email = 'leaky.marker@x.com';
    await request(app.getHttpServer())
      .post('/users')
      .send({ ...VALID, email })
      .expect(201);
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({ ...VALID, email });
    expect(JSON.stringify(res.body)).not.toContain(email);
  });

  it('400 with { error: "password_debil" } when password is too short', async () => {
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({ email: 'ana@x.com', password: 'Ab1!short' });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'password_debil' });
  });

  it('400 with { error: "password_debil" } when password has no uppercase', async () => {
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({ email: 'ana@x.com', password: 'segur0!passw0rd' });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'password_debil' });
  });

  it('400 with { error: "email_invalido" } when email is malformed', async () => {
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({ email: 'not-an-email', password: 'Segur0!Passw0rd' });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'email_invalido' });
  });

  it('400 when extra fields are present — whitelist blocks isAdmin from reaching the controller', async () => {
    const res = await request(app.getHttpServer())
      .post('/users')
      .send({ ...VALID, isAdmin: true });
    expect(res.status).toBe(400);
    // The message is class-validator's own for whitelist violations; the
    // shape is still { error: "<message>" }.
    const body = res.body as { error: string };
    expect(body.error).toEqual(expect.any(String));
    expect(body.error).toContain('isAdmin');
  });
});

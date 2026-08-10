import { BadRequestException, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { ValidationError } from 'class-validator';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(
    new ValidationPipe({
      // whitelist strips unknown properties; forbidNonWhitelisted rejects
      // them outright with 400. Together they close the "isAdmin: true"
      // leak — a body field the DTO does not declare never reaches the
      // controller.
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      // The default validation exception body is { statusCode, message[],
      // error }. The spec requires { error: "<code>" } with exactly one
      // string. Custom exceptionFactory maps the first constraint message
      // of the first error to that shape. Codes come from the DTO's
      // constraint messages ("email_invalido", "password_debil").
      exceptionFactory: (errors: ValidationError[]) => {
        const first = errors[0];
        const firstMessage =
          Object.values(first?.constraints ?? {})[0] ?? 'invalid_payload';
        return new BadRequestException({ error: firstMessage });
      },
    }),
  );
  await app.listen(process.env.PORT ?? 3000);
}
void bootstrap();

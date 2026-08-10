import {
  Body,
  ConflictException,
  Controller,
  HttpCode,
  Post,
} from '@nestjs/common';
import { CreateUserDto } from './dto/create-user.dto';
import { UserResponseDto } from './dto/user.response.dto';
import {
  EmailAlreadyRegisteredError,
  UserRecord,
  UsersService,
} from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly service: UsersService) {}

  @Post()
  @HttpCode(201)
  async create(@Body() dto: CreateUserDto): Promise<UserResponseDto> {
    try {
      const record = await this.service.create(dto.email, dto.password);
      return toResponse(record);
    } catch (err) {
      if (err instanceof EmailAlreadyRegisteredError) {
        // The error message includes the email — do NOT forward it. The
        // body carries only the contract string; the incoming email is
        // already known to the client.
        throw new ConflictException({ error: 'email_ya_registrado' });
      }
      throw err;
    }
  }
}

// Explicit mapping — a res.json(record) would ship the passwordHash. Placing
// this next to the controller keeps the two things (mapping and the endpoint
// that uses it) reviewable together.
const toResponse = (record: UserRecord): UserResponseDto => ({
  id: record.id,
  email: record.email,
});

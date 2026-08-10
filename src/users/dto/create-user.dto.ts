import { IsEmail, IsNotEmpty, Matches, MinLength } from 'class-validator';

// Reglas de fuerza del password (issue #1):
// - min 12 caracteres
// - al menos una mayuscula, una minuscula, un digito y un caracter no alfanumerico
//
// Se declaran con Matches en vez de con una funcion custom para que el mensaje
// de error viaje como parte del constraint. Un lookahead por familia detecta
// la ausencia sin depender del orden; el . final acepta cualquier caracter,
// asi que el propio MinLength es quien impone el largo.
const PASSWORD_FUERTE = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).+$/;

export class CreateUserDto {
  @IsEmail({}, { message: 'email_invalido' })
  @IsNotEmpty({ message: 'email_invalido' })
  email!: string;

  @IsNotEmpty({ message: 'password_debil' })
  @MinLength(12, { message: 'password_debil' })
  @Matches(PASSWORD_FUERTE, { message: 'password_debil' })
  password!: string;
}

// El DTO se prueba en aislamiento: sin controller, sin service. Solo la
// validacion. Si la validacion falla aqui, ninguna otra capa la salva —
// class-validator corre en el pipe global antes de que el request llegue
// al controller.
import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { CreateUserDto } from './create-user.dto';

const build = (overrides: Partial<CreateUserDto> = {}): CreateUserDto =>
  plainToInstance(CreateUserDto, {
    email: 'ana@x.com',
    password: 'Segur0!Passw0rd',
    ...overrides,
  });

const propiedadesConError = async (dto: CreateUserDto): Promise<string[]> => {
  const errores = await validate(dto);
  return errores.map((e) => e.property);
};

describe('CreateUserDto', () => {
  it('acepta un payload con email valido y password fuerte', async () => {
    expect(await propiedadesConError(build())).toEqual([]);
  });

  it('rechaza cuando el email no es un email', async () => {
    const props = await propiedadesConError(build({ email: 'no-es-email' }));
    expect(props).toContain('email');
  });

  it('rechaza cuando el email esta vacio', async () => {
    const props = await propiedadesConError(build({ email: '' }));
    expect(props).toContain('email');
  });

  it('rechaza password de menos de 12 caracteres', async () => {
    const props = await propiedadesConError(build({ password: 'Ab1!short' }));
    expect(props).toContain('password');
  });

  it('rechaza password sin mayuscula', async () => {
    const props = await propiedadesConError(
      build({ password: 'segur0!passw0rd' }),
    );
    expect(props).toContain('password');
  });

  it('rechaza password sin minuscula', async () => {
    const props = await propiedadesConError(
      build({ password: 'SEGUR0!PASSW0RD' }),
    );
    expect(props).toContain('password');
  });

  it('rechaza password sin digito', async () => {
    const props = await propiedadesConError(
      build({ password: 'SeguroPassword!' }),
    );
    expect(props).toContain('password');
  });

  it('rechaza password sin caracter no alfanumerico', async () => {
    const props = await propiedadesConError(
      build({ password: 'Segur0Passw0rdX' }),
    );
    expect(props).toContain('password');
  });
});

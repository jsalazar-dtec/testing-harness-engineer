// Response shape for POST /users. The controller maps UserRecord (which
// carries passwordHash and createdAt) to this DTO explicitly — a res.json
// of the record would leak the hash. Keeping the mapping in one place, in
// one file, makes the leak surface auditable.
export interface UserResponseDto {
  id: string;
  email: string;
}

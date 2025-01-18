use dojo_starter::models::{
    Room, Position, PieceType, PieceColor, CastlingRights, GameState, Player, ChessBoard,
    ChessPiece,
};


use core::iter::{Iterator, IntoIterator};
use core::nullable::NullableTrait;
use core::dict::{Felt252Dict, Felt252DictEntryTrait};
#[starknet::interface]
trait RoomCreationTrait<T> {
    fn create_room(ref self: T) -> u32;
    fn join_room(ref self: T, room_id: u32);
}

#[starknet::interface]
trait GameStartedTrait<T> {
    fn start_game(ref self: T, room_id: u32);
    // fn make_move(ref self: T, room_id: u32, piece: PieceType, to_position: Position);
    fn make_move(ref self: T, room_id: u32, piece: PieceType, to_position: Position);
    
}

// dojo decorator
#[dojo::contract]
pub mod actions {
    use super::{
        GameStartedTrait, RoomCreationTrait, Position, PieceType, CastlingRights, PieceColor, Room,
        GameState, Player, ChessPiece, ChessBoard, generate_chess960_board, validate_rook_move,
        is_obstructed, validate_bishop_move, validate_queen_move, validate_pawn_move,
        validate_king_move, validate_knight_move,
    };
    use starknet::{ContractAddress, get_caller_address};
    use dojo::model::{ModelStorage, ModelValueStorage};
    use dojo::event::EventStorage;
    use dojo::world::WorldStorage;
    use dojo::world::IWorldDispatcherTrait;
    
    #[derive(Drop, Serde, Debug)]
    #[dojo::event]
    pub struct PlayerJoined {
        #[key]
        pub room_id: u32,
        pub player: ContractAddress,
    }

    #[derive(Drop, Serde, Debug)]
    #[dojo::event]
    pub struct ErrorEvent {
        #[key]
        pub message_id: u32,
        pub message: ByteArray,
    }

    #[derive(Drop, Serde, Debug)]
    #[dojo::event]
    pub struct GameStarted {
        #[key]
        pub room_id: u32,
        pub game_started: bool,
    }

    #[derive(Drop, Serde, Debug)]
    #[dojo::event]
    pub struct MoveMade {
        #[key]
        pub room_id: u32,
        pub piece: PieceType,
        pub from: Position,
        pub to: Position,
    }


    #[abi(embed_v0)]
    impl RoomCreationImpl of RoomCreationTrait<ContractState> {
        fn create_room(ref self: ContractState) -> u32 {
            let mut world = self.world_default();
            let creator_address = get_caller_address();

            let room_id = world.dispatcher.uuid();

            let creator_player = Player {
                room_id, address: creator_address, color: PieceColor::White,
            };

            let new_room = Room {
                room_id, players: creator_player, player_count: 1, game_started: false,
            };

            world.write_model(@new_room);

            return room_id;
        }


        fn join_room(ref self: ContractState, room_id: u32) {
            let mut world = self.world_default();
            let joiner_address = get_caller_address();

            let mut room: Room = world.read_model(room_id);

            // if room_option.is_none() {
            //     return;
            // }

            // let mut room = room_option.unwrap();

            let joiner_player = Player {
                room_id, address: joiner_address, color: PieceColor::Black,
            };

            room.players = joiner_player;
            room.player_count += 1;

            world.emit_event(@PlayerJoined { room_id, player: joiner_address });
            world.write_model(@room);
        }
    }


    #[abi(embed_v0)]
    impl GameStartedImpl of GameStartedTrait<ContractState> {
        fn start_game(ref self: ContractState, room_id: u32) {
            let mut world = self.world_default();
            let mut room: Room = world.read_model(room_id);

            if room.player_count != 2 {
                panic!("Cannot start game: Room is not full.");
            }

            let initial_board = generate_chess960_board();
            let mut move_history: Array = ArrayTrait::new();
            let _game_state = GameState {
                room_id,
                board: ChessBoard {
                    room_id,
                    active_color: PieceColor::White,
                    squares: initial_board,
                    castling_rights: CastlingRights::default(),
                    en_passant_target: Option::None,
                },
                move_history,
                is_check: false,
                is_checkmate: false,
                is_stalemate: false,
                fifty_move_rule_counter: 0,
            };

            room.game_started = true;
            world.write_model(@room);
            world.emit_event(@GameStarted { room_id, game_started: true });
        }


        fn make_move(
            ref self: ContractState, room_id: u32, piece: PieceType, to_position: Position,
        ) {
            let mut world = self.world_default();
            let mut game_state: GameState = world.read_model(room_id);
            let mut current_player: Player = world.read_model(room_id);

            // Validate turn
            let active_player = get_caller_address();
            if active_player != current_player.address {
                panic!("Not your turn!");
            }

            // Logic to validate and execute the move...
            let mut piece_to_move = Option::None;

            // Find the piece on the board
            for square in game_state.board.squares {
                match square {
                    Option::Some(chess_piece) => {
                        if chess_piece.piece_type == piece
                            && chess_piece.color == current_player.color {
                            piece_to_move = Option::Some(chess_piece);
                            break;
                        }
                    },
                    Option::None => {} // Skip empty squares
                }
            };

            match piece_to_move {
                Option::Some(piece) => {
                    // Validate the move based on piece type
                    let valid_moves = match piece.piece_type {
                        PieceType::King => validate_king_move(piece.position, @game_state),
                        PieceType::Queen => validate_queen_move(piece.position, @game_state),
                        PieceType::Rook => {
                            // Validate rook move, checking the chessboard boundaries and potential
                            // blockages
                            validate_rook_move(piece.position, @game_state)
                        },
                        PieceType::Bishop => validate_bishop_move(piece.position, @game_state),
                        PieceType::Knight => validate_knight_move(piece.position, @game_state),
                        PieceType::Pawn => validate_pawn_move(
                            piece.position, @game_state, current_player.color,
                        ),
                    };

                    let mut valid_move_found = false;
                    for valid_pos in valid_moves {
                        if *valid_pos == to_position {
                            valid_move_found = true;
                            break;
                        }
                    };

                    if !valid_move_found {
                        panic!("Invalid move!");
                    }

                    // Update the piece position
                    let mut updated_squares = game_state.board.squares;
                    for i in 0..updated_squares.len() {
                        if let Option::Some(existing_piece) = updated_squares[i] {
                            if *existing_piece.position == piece.position {
                                // Replace the existing piece with a new one, updating its position
                                // and has_moved
                                updated_squares
                                    .at(i) =
                                        Option::Some(
                                            ChessPiece {
                                                position: to_position,
                                                has_moved: true,
                                                ..*existing_piece // Copy all other fields from the existing piece
                                            },
                                        );
                                break;
                            }
                        } 
                    };
                    
                    game_state.board.squares = updated_squares;

                    // Switch the turn to the next player
                    game_state
                        .board
                        .active_color =
                            if current_player.color == PieceColor::White {
                                PieceColor::Black
                            } else {
                                PieceColor::White
                            };

                    // Emit move event
                    // world
                    //     .emit_event(
                    //         @MoveMade { room_id, piece, from: piece.position, to: to_position },
                    //     );

                    // Write the updated game state
                    world.write_model(@game_state);
                },
                Option::None => panic!("No piece of the specified type and color found!"),
            }
        }
    }




    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Use the default namespace "dojo_starter". This function is handy since the ByteArray
        /// can't be const.
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"dojo_starter")
        }
    }
}


fn generate_chess960_board() -> Array<Option<ChessPiece>> {
    let mut board: Array<Option<ChessPiece>> = ArrayTrait::new();

    // Step 1: Define initial positions for pawns
    let mut back_rank_positions: Array<PieceType> = array![
        PieceType::Rook,
        PieceType::Knight,
        PieceType::Bishop,
        PieceType::Queen,
        PieceType::King,
        PieceType::Bishop,
        PieceType::Knight,
        PieceType::Rook,
    ];

    // Initialize a mutable index
    let mut col: u32 = 0;
    let mut col2: u32 = 0;

    while col < back_rank_positions.len() {
        // Access the current piece type
        let piece_type = back_rank_positions[col];

        // Add white back-rank pieces
        board
            .append(
                Option::Some(
                    ChessPiece {
                        piece_type: *piece_type,
                        position: Position { x: col, y: 0 },
                        color: PieceColor::White,
                        has_moved: false,
                    },
                ),
            );

        // Add black back-rank pieces
        board
            .append(
                Option::Some(
                    ChessPiece {
                        piece_type: *piece_type,
                        position: Position { x: col, y: 7 },
                        color: PieceColor::Black,
                        has_moved: false,
                    },
                ),
            );

        // Increment the index
        col += 1;
    };

    // Step 2: Add pawns
    while col2 < 8 {
        // Add white pawns
        board
            .append(
                Option::Some(
                    ChessPiece {
                        piece_type: PieceType::Pawn,
                        position: Position { x: col, y: 1 },
                        color: PieceColor::White,
                        has_moved: false,
                    },
                ),
            );

        // Add black pawns
        board
            .append(
                Option::Some(
                    ChessPiece {
                        piece_type: PieceType::Pawn,
                        position: Position { x: col, y: 6 },
                        color: PieceColor::Black,
                        has_moved: false,
                    },
                ),
            );

        col2 += 1;
    };

    // Step 3: Add empty squares (represented by `None`)
    let mut row: u32 = 2;
    while row < 6 {
        let mut col: u32 = 0;
        while col < 8 {
            board.append(Option::None); // Empty squares are represented by `None`
            col += 1;
        };
        row += 1;
    };

    board
}
// fn make_move(ref self: ContractState, room_id: u32, piece_id: u32, to_position: Position) {
//     let mut world = self.world_default();
//     let mut game_state: GameState = world.read_model(room_id);

//     // Validate turn
//     let active_player = get_caller_address();
//     if active_player != game_state.board.active_color {
//         panic!("Not your turn!");
//     }

//     // Logic to validate and execute the move...

//     world.write_model(@game_state);
//     world.emit_event(@MoveMade {
//         room_id,
//         piece_id,
//         from: game_state.board.squares[piece_id].position,
//         to: to_position,
//     });
// }

fn validate_rook_move(from: Position, game_state: @GameState) -> Array<Position> {
    // use core::iter::{Iterator, IntoIterator};
    let mut valid_moves: Array<Position> = ArrayTrait::new();

    // Check left
    let mut dx = from.x;
    while dx > 0 {
        dx -= 1;
        let pos = Position { x: dx, y: from.y };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check right
    let mut dx2 = from.x + 1;
    while dx2 < 8 {
        let pos = Position { x: dx2, y: from.y };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
        dx2 += 1;
    };

    // Check up
    let mut dy = from.y;
    while dy > 0 {
        dy -= 1;
        let pos = Position { x: from.x, y: dy };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check down
    let mut dy2 = from.y + 1;
    while dy2 < 8 {
        let pos = Position { x: from.x, y: dy2 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
        dy2 += 1;
    };

    valid_moves
}


fn validate_bishop_move(from: Position, game_state: @GameState) -> Array<Position> {
    // use core::iter::{Iterator, IntoIterator};
    let mut valid_moves: Array<Position> = ArrayTrait::new();

    // Check top-left diagonal
    let mut dx = from.x;
    let mut dy = from.y;
    while dx > 0 && dy > 0 {
        dx -= 1;
        dy -= 1;
        let pos = Position { x: dx, y: dy };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check top-right diagonal
    let mut dx2 = from.x + 1;
    let mut dy2 = from.y;
    while dx2 < 8 && dy2 > 0 {
        dx2 += 1;
        dy2 -= 1;
        let pos = Position { x: dx2, y: dy2 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check bottom-left diagonal
    let mut dx3 = from.x;
    let mut dy3 = from.y + 1;
    while dx3 > 0 && dy3 < 8 {
        dx3 -= 1;
        dy3 += 1;
        let pos = Position { x: dx3, y: dy3 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check bottom-right diagonal
    let mut dx4 = from.x + 1;
    let mut dy4 = from.y + 1;
    while dx4 < 8 && dy4 < 8 {
        dx4 += 1;
        dy4 += 1;
        let pos = Position { x: dx4, y: dy4 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    valid_moves
}

fn validate_queen_move(from: Position, game_state: @GameState) -> Array<Position> {
    // use core::iter::{Iterator, IntoIterator};
    let mut valid_moves: Array<Position> = ArrayTrait::new();

    // Rook-like moves (horizontal and vertical)
    // Check left
    let mut dx = from.x;
    while dx > 0 {
        dx -= 1;
        let pos = Position { x: dx, y: from.y };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check right
    let mut dx2 = from.x + 1;
    while dx2 < 8 {
        let pos = Position { x: dx2, y: from.y };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
        dx2 += 1;
    };

    // Check up
    let mut dy = from.y;
    while dy > 0 {
        dy -= 1;
        let pos = Position { x: from.x, y: dy };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check down
    let mut dy2 = from.y + 1;
    while dy2 < 8 {
        let pos = Position { x: from.x, y: dy2 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
        dy2 += 1;
    };

    // Bishop-like moves (diagonal)
    // Check top-left diagonal
    let mut dx3 = from.x;
    let mut dy3 = from.y;
    while dx3 > 0 && dy3 > 0 {
        dx3 -= 1;
        dy3 -= 1;
        let pos = Position { x: dx3, y: dy3 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check top-right diagonal
    let mut dx4 = from.x + 1;
    let mut dy4 = from.y;
    while dx4 < 8 && dy4 > 0 {
        dx4 += 1;
        dy4 -= 1;
        let pos = Position { x: dx4, y: dy4 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check bottom-left diagonal
    let mut dx5 = from.x;
    let mut dy5 = from.y + 1;
    while dx5 > 0 && dy5 < 8 {
        dx5 -= 1;
        dy5 += 1;
        let pos = Position { x: dx5, y: dy5 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    // Check bottom-right diagonal
    let mut dx6 = from.x + 1;
    let mut dy6 = from.y + 1;
    while dx6 < 8 && dy6 < 8 {
        dx6 += 1;
        dy6 += 1;
        let pos = Position { x: dx6, y: dy6 };
        if is_obstructed(pos, game_state) {
            break; // Stop if an obstruction is encountered
        }
        valid_moves.append(pos); // Add valid position
    };

    valid_moves
}

fn validate_pawn_move(
    from: Position, game_state: @GameState, color: PieceColor,
) -> Array<Position> {

    // use core::iter::{Iterator, IntoIterator};
    let mut valid_moves: Array<Position> = ArrayTrait::new();

    // Determine movement direction and starting row based on the color
    let (direction, _start_row) = match color {
        PieceColor::White => (1, 1), // White moves "up" the board (y decreases)
        PieceColor::Black => (0, 6) // Black moves "down" the board (y increases)
    };

    // Forward movement (1 square)
    let forward_y = if direction == 0 {
        from.y - 1
    } else {
        from.y + 1
    };

    let forward_pos = Position { x: from.x, y: forward_y };

    if !is_obstructed(forward_pos, game_state) {
        valid_moves.append(forward_pos);
        // Forward movement (2 squares) if it's the pawn's first move
    };
    valid_moves
}


fn validate_king_move(from: Position, game_state: @GameState) -> Array<Position> {
    // use core::iter::{Iterator, IntoIterator};

    let mut valid_moves: Array<Position> = ArrayTrait::new();

    let directions: Array<(i32, i32)> = array![
        (-1_i32, 0_i32),   // Left
        (1_i32, 0_i32),    // Right
        (0_i32, -1_i32),   // Up
        (0_i32, 1_i32),    // Down
        (-1_i32, -1_i32),  // Top-left
        (1_i32, -1_i32),   // Top-right
        (-1_i32, 1_i32),   // Bottom-left
        (1_i32, 1_i32)     // Bottom-right
    ];

    let directions_span: Span<(i32, i32)> = directions.span();

    let mut iter = directions_span.into_iter();

    loop {
        match iter.next() {
            Option::Some(item) => {
                let dx = item[0]; // Extract x-offset
                let dy = item[1]; // Extract y-offset

                // Safely calculate the new positions
                let new_x = from.x + dx;
                let new_y = from.y + dy;

                // Ensure the move is within board boundaries
                if new_x >= 0 && new_x < 8 && new_y >= 0 && new_y < 8 {
                    let pos = Position { x: new_x, y: new_y };
                    if !is_obstructed(pos, game_state) {
                        valid_moves.append(pos); // Add valid position
                    }
                }
            },
            Option::None => { break; },
        };
    };

    valid_moves
}


fn validate_knight_move(from: Position, game_state: @GameState) -> Array<Position> {
    let mut valid_moves: Array<Position> = ArrayTrait::new();

     // Define all possible knight move offsets
     let knight_moves: Array<(i32, i32)> = array![
        (2, 1), (1, 2), (-1, 2), (-2, 1),
        (-2, -1), (-1, -2), (1, -2), (2, -1)
    ];

    let knight_moves_span: Span<(i32, i32)> = knight_moves.span();

    let mut iter = knight_moves_span.into_iter();

    loop {
        match iter.next() {
            Option::Some(item) => {
                let dx = item[0]; // Extract x-offset
                let dy = item[1]; // Extract y-offset
                let new_x = from.x + dx;
                let new_y = from.y + dy;

                // Ensure the move is within board boundaries
                if new_x >= 0 && new_x < 8 && new_y >= 0 && new_y < 8 {
                    let pos = Position { x: new_x, y: new_y };
                    if !is_obstructed(pos, game_state) {
                        valid_moves.append(pos); // Add valid position
                    }
                }
            },
            Option::None => { break; },
        };
    };
    valid_moves
}


fn is_obstructed(pos: Position, game_state: @GameState) -> bool {
    let arr = game_state.board.squares;
    let length = arr.len(); // Get the length of the array
    let mut obstructed = false; // Flag to track obstruction

    // Iterate over the array using indexing
    for i in 0..length {
        match arr[i] {
            Option::Some(piece) => {
                if *piece.position.x == pos.x && *piece.position.y == pos.y {
                    obstructed = true; // Obstruction found, set flag
                }
            },
            Option::None => {},
        }
    };

    obstructed // Return the result after the loop
}
// fn is_obstructed(pos: Position, game_state: @GameState) -> bool {

//     let mut arr =game_state.board.squares;
//     let mut arr2 =*arr;
//     let mut iter = arr2.into_iter(); // Create an iterator over the squares

//     loop {
//         match iter.next() {
//             Option::Some(piece_opt) => {
//                 if let Option::Some(piece) = piece_opt {
//                     if piece.position == pos {
//                         return true; // Obstruction found
//                     }
//                 }
//             },
//             Option::None => {
//                 break; // Exit the loop when all elements are processed
//             }
//         }
//     };
//     false // No obstruction found
// }






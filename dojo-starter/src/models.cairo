use starknet::ContractAddress;
use starknet::storage::{Vec};

use core::dict::Felt252Dict;
use core::nullable::NullableTrait;
use core::num::traits::WrappingAdd;

#[derive(Drop, Serde, Debug)]
#[dojo::model]
pub struct Room {
    #[key]
    pub room_id: u32, // Unique identifier for the room.
    pub players: Player, // Addresses of the 2 players in the room.
    pub player_count: u8, // Current number of players in the room.
    pub game_started: bool, // Whether the game has started.
}


#[derive(Drop, Serde, Debug)]
#[dojo::model]
pub struct ChessPiece {
    #[key]
    pub piece_type: PieceType,
    #[key] // Enum: White, Black
    pub position: Position,
    #[key] // Enum: King, Queen, Rook, Bishop, Knight, Pawn
    pub color: PieceColor,
    // Current position on the board
    pub has_moved: bool, // Tracks if the piece has moved (useful for castling/pawn moves)
}

#[derive(Serde, Copy, Drop, Introspect, PartialEq, Debug)]
pub enum PieceType {
    King,
    Queen,
    Rook,
    Bishop,
    Knight,
    Pawn,
}

impl PieceTypeIntoFelt252 of Into<PieceType, felt252> {
    fn into(self: PieceType) -> felt252 {
        match self {
            PieceType::King => 0,
            PieceType::Queen => 1,
            PieceType::Rook => 2,
            PieceType::Bishop => 3,
            PieceType::Knight => 4,
            PieceType::Pawn => 5,
        }
    }
}

#[derive(Serde, Copy, Drop, Introspect, PartialEq, Debug)]
pub enum PieceColor {
    White,
    Black,
}

impl PieceColorIntoFelt252 of Into<PieceColor, felt252> {
    fn into(self: PieceColor) -> felt252 {
        match self {
            PieceColor::White => 0,
            PieceColor::Black => 1,
        }
    }
}


#[derive(Copy, Drop, Serde, IntrospectPacked, Debug)]
pub struct Position {
    #[key]
    pub x: u32,
    pub y: u32,
}

#[derive(Drop, Serde, Debug)]
#[dojo::model]
pub struct Move {
    #[key] // The piece being moved
    pub from: Position,
    #[key] // Starting position
    pub to: Position, // Target position
    pub piece: ChessPiece,
    pub captured_piece: Option<ChessPiece>, // Piece captured, if any
    pub promotion: Option<PieceType>, // Promotion type (only for pawns)
    pub move_type: MoveType, // Enum: Normal, Castling, En Passant, Promotion
}

#[derive(Serde, Copy, Drop, Introspect, PartialEq, Debug)]
pub enum MoveType {
    Normal,
    Castling,
    EnPassant,
    Promotion,
}


impl MoveTypeIntoFelt252 of Into<MoveType, felt252> {
    fn into(self: MoveType) -> felt252 {
        match self {
            MoveType::Normal => 0,
            MoveType::Castling => 1,
            MoveType::EnPassant => 2,
            MoveType::Promotion => 3,
        }
    }
}


#[derive(Drop, Serde,Introspect, Debug)]
#[dojo::model]
pub struct ChessBoard {
    #[key]
    pub room_id: u32,
    #[key] // 8x8 board with pieces or empty squares
    pub active_color: PieceColor,
    pub squares: Array<Option<ChessPiece>>, // Current player (White or Black)
    pub castling_rights: CastlingRights, // Tracks castling availability
    pub en_passant_target: Option<Position>, // Target square for en passant, if applicable
}

#[derive(Drop, Serde, Debug)]
#[dojo::model]
pub struct CastlingRights {
    #[key]
    pub room_id: u32,
    pub white_kingside: bool,
    pub white_queenside: bool,
    pub black_kingside: bool,
    pub black_queenside: bool,
}

#[derive(Drop, Serde, Debug)]
#[dojo::model]
pub struct GameState {
    #[key]
    pub room_id: u32,
    pub board: ChessBoard, // Current board state
    pub move_history: Array<Move>, // List of moves made
    pub is_check: bool, // Is the current player in check?
    pub is_checkmate: bool, // Is it a checkmate?
    pub is_stalemate: bool, // Is it a stalemate?
    pub fifty_move_rule_counter: u8, // Counter for the 50-move rule
}

#[derive(Drop, Serde, Debug)]
#[dojo::model]
pub struct Player {
    #[key]
    pub room_id: u32,
    #[key] // Player's name
    pub color: PieceColor, // White or Black
    pub address: ContractAddress,
}






















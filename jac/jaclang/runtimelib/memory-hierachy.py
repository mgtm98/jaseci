"""Base memory hierachy implementation."""

from __future__ import annotations

from dataclasses import dataclass, field
from pickle import dumps, loads
import os
from typing import Any, Iterable, TypeVar
from uuid import UUID

from pymongo import MongoClient, UpdateOne

from .archetype import Anchor, TANCH

import redis

from .memory import Memory

ID = TypeVar("ID")


@dataclass
class MultiHierarchyMemory:

    def __init__(self):
        self.mem = Memory()
        self.redis = RedisDB()
        self.mongo = MongoDB()

    # ---- DOWNSTREAM (READS) ----
    def find_by_id(self, id: UUID) -> Anchor | None:
        # 1. Memory
        if anchor := self.mem.find_by_id(id):
            return anchor
        # 2. Redis
        if anchor := self.redis.find_by_id(id):
            self.mem.set(anchor)
            return anchor
        # 3. MongoDB
        if anchor := self.mongo.find_by_id(id):
            self.mem.set(anchor)
            self.redis.set(anchor)
            return anchor

        return None

    # ---- UPSTREAM (WRITES) ----
    def commit(self, anchor: Anchor | None = None):
        gc = self.mem.get_gc()
        memory = self.mem.get_mem()
        if anchor:
            if anchor in gc:
                self.delete(anchor)
                self.mem.remove_from_gc(anchor)
            else:
                self.redis.set(anchor)
                self.mongo.set(anchor)
            return

        for anchor in gc:
            self.delete(anchor)
            self.mem.remove_from_gc(anchor)

        anchors = set(memory.values())
        self.sync(anchors)

    def close(self):
        self.commit()
        self.mem.close()

    def sync(self, anchors):
        self.redis.commit(keys=anchors)
        self.mongo.commit(keys=anchors)

    def delete(self, anchor: Anchor):
        self.mem.remove(anchor)
        self.redis.remove(anchor)
        self.mongo.remove(anchor)

    def set(self, anchor: TANCH):
        self.mem.set(anchor)


@dataclass
class MongoDB:  # Memory[UUID, Anchor]):
    """MongoDB handler."""

    client: MongoClient | None = field(default=None)
    db_name: str = "jac_db"
    collection_name: str = "anchors"
    mongo_url = os.environ.get(
        "MONGODB_URI",
        "mongodb+srv://juzailmlwork_db_user:e5OTI7p2DkaaGHnL@cluster0.e8eqk4i.mongodb.net/?appName=Cluster0/",
    )

    def __post_init__(self) -> None:
        """Initialize Mongodb."""
        if self.client is None:
            self.client = MongoClient(self.mongo_url)

        self.db = self.client[self.db_name]
        self.collection = self.db[self.collection_name]

    def _to_uuid(self, id: UUID | str) -> UUID:
        if not isinstance(id, UUID):
            return UUID(str(id))
        return id

    def _load_anchor(self, raw: dict[str, Any]) -> TANCH | None:
        try:
            return loads(raw["data"])
        except Exception:
            return None

    def set(self, anchor: Anchor) -> None:
        """
        Save anchor to MongoDB, exactly like ShelfStorage:
        - Save all anchors (no empty NodeAnchor skipping)
        - Update NodeAnchor edges
        - Respect write and connect access
        """
        from jaclang.runtimelib.machine import JacMachineInterface as Jac
        from .archetype import NodeAnchor

        _id = self._to_uuid(anchor.id)
        try:
            current_hash = hash(dumps(anchor))
            print("anchor hash in mongodb is ", anchor.hash)
            print("current hash in mongodb is", current_hash)

        except Exception:
            return

        if getattr(anchor, "hash", None) == current_hash:
            return

        # fetch existing
        db_doc = self.collection.find_one({"_id": str(_id)})
        stored_anchor = self._load_anchor(db_doc) if db_doc else None
        # update edges if NodeAnchor
        if (
            stored_anchor
            and isinstance(stored_anchor, NodeAnchor)
            and isinstance(anchor, NodeAnchor)
            and getattr(stored_anchor, "edges", None) != getattr(anchor, "edges", None)
            and Jac.check_connect_access(anchor)
        ):
            stored_anchor.edges = anchor.edges
            base_anchor = stored_anchor
        else:
            base_anchor = anchor

        # update access/archetype if allowed
        if stored_anchor and Jac.check_write_access(anchor):
            try:
                if hash(dumps(stored_anchor.access)) != hash(dumps(anchor.access)):
                    stored_anchor.access = anchor.access
                if hash(dumps(stored_anchor.archetype)) != hash(
                    dumps(anchor.archetype)
                ):
                    stored_anchor.archetype = anchor.archetype
                final_anchor = stored_anchor
            except Exception:
                final_anchor = anchor
        else:
            final_anchor = base_anchor

        # save to MongoDB
        try:
            data_blob = dumps(final_anchor)
        except Exception:
            return

        self.collection.update_one(
            {"_id": str(_id)},
            {"$set": {"data": data_blob, "type": type(final_anchor).__name__}},
            upsert=True,
        )
        # print("uploaded anchor to item to mongodb ")

    def remove(self, anchor: TANCH) -> None:
        _id = self._to_uuid(anchor.id)
        self.collection.delete_one({"_id": str(_id)})

    # def find(
    #     self,
    #     ids: UUID | Iterable[UUID],
    #     filter: Callable | None = None,
    # ) -> Generator[Anchor, None, None]:
    #     if not isinstance(ids, Iterable) or isinstance(ids, (str, bytes)):
    #         ids = [ids]

    #     for id in ids:
    #         _id = self._to_uuid(id)

    #         # check memory first
    #         obj = self.__mem__.get(_id)
    #         if obj:
    #             if not filter or filter(obj):
    #                 yield obj
    #             continue

    #         # fetch from DB
    #         db_doc = self.collection.find_one({"_id": str(_id)})
    #         if db_doc:
    #             anchor = self._load_anchor(db_doc)
    #             if anchor is None:
    #                 continue
    #             self.__mem__[_id] = anchor
    #             yield anchor

    # def find_one(
    #     self,
    #     ids: UUID | Iterable[UUID],
    #     filter: Callable[[TANCH], TANCH] | None = None,
    # ) -> Anchor | None:
    #     return next(self.find(ids, filter), None)

    def find_by_id(self, id: UUID) -> Anchor | None:
        _id = self._to_uuid(id)
        db_obj = self.collection.find_one({"_id": str(_id)})
        if db_obj:
            anchor = self._load_anchor(db_obj)
            if anchor:
                return anchor
        return None

    def commit_bulk(self, anchors) -> None:
        """
        Faster bulk commit:
        - Deletes anchors in GC
        - Saves only updated anchors
        - Uses MongoDB bulk_write for speed
        """
        from jaclang.runtimelib.machine import JacMachineInterface as Jac
        from .archetype import NodeAnchor

        ops: list = []

        for anc in anchors:
            _id = self._to_uuid(anc.id)

            try:

                current_hash = hash(dumps(anc))
            except Exception:
                continue
            print("anchor hash in mongodb is ", anc.hash)
            print("current hash in mongodb is", current_hash)
            # Skip if hash unchanged → no need to save
            if getattr(anc, "hash", None) == current_hash:
                continue

            # Need to fetch stored anchor only once
            db_doc = self.collection.find_one({"_id": str(_id)})
            stored_anchor = self._load_anchor(db_doc) if db_doc else None

            # ---- Edge merging logic ----
            if (
                stored_anchor
                and isinstance(stored_anchor, NodeAnchor)
                and isinstance(anc, NodeAnchor)
                and getattr(stored_anchor, "edges", None) != getattr(anc, "edges", None)
                and Jac.check_connect_access(anc)
            ):
                stored_anchor.edges = anc.edges
                working_anchor = stored_anchor
            else:
                working_anchor = anc

            # ---- Access + archetype update logic ----
            if stored_anchor and Jac.check_write_access(anc):
                try:
                    if hash(dumps(stored_anchor.access)) != hash(dumps(anc.access)):
                        stored_anchor.access = anc.access
                    if hash(dumps(stored_anchor.archetype)) != hash(
                        dumps(anc.archetype)
                    ):
                        stored_anchor.archetype = anc.archetype
                    working_anchor = stored_anchor
                except Exception:
                    working_anchor = anc
            # ---- Serialize ----
            try:
                blob = dumps(working_anchor)
            except Exception:
                continue

            ops.append(
                UpdateOne(
                    {"_id": str(_id)},
                    {"$set": {"data": blob, "type": type(working_anchor).__name__}},
                    upsert=True,
                )
            )

        if ops:
            print(f"Performing bulk write with {len(ops)} operations...")
            self.collection.bulk_write(ops)

    def commit(self, anchor: TANCH | None = None, keys: Iterable[Anchor] = []) -> None:
        if anchor:
            self.set(anchor)
            return
        if keys:
            self.commit_bulk(keys)


@dataclass
class RedisDB:  # Memory[UUID, Anchor]):
    """Redis-based Memory Handler."""

    redis_url: str = os.environ.get(
        "MONGODB_URI", "redis://:mypassword123@localhost:6379/0"
    )
    redis_client: redis.Redis | None = field(default=None)

    def __post_init__(self) -> None:
        """Initialize Redis."""

        if self.redis_client is None:
            self.redis_client = redis.from_url(self.redis_url)

    def _redis_key(self, id: UUID) -> str:
        return f"anchor:{str(id)}"

    def _to_uuid(self, id: UUID | str) -> UUID:
        if not isinstance(id, UUID):
            return UUID(str(id))
        return id

    def _load_anchor_from_redis(self, id: UUID) -> Anchor | None:
        if self.redis_client is None:
            return None
        key = self._redis_key(id)
        raw = self.redis_client.get(key)
        if not raw:
            return None
        try:
            return loads(raw)
        except Exception:
            return None

    def set(self, anchor: Anchor) -> None:
        """Save to MongoDB AND Redis."""
        if self.redis_client is None:
            return
        self.redis_client.set(self._redis_key(anchor.id), dumps(anchor))

    def remove(self, anchor: Anchor) -> None:
        """Delete from MongoDB AND Redis."""
        if self.redis_client is None:
            return None
        self.redis_client.delete(self._redis_key(anchor.id))

    # def find(
    #     self,
    #     ids: UUID | Iterable[UUID],
    #     filter: Callable[[Anchor], bool] | None = None,
    # ) -> Generator[Anchor, None, None]:

    #     if not isinstance(ids, Iterable):
    #         ids = [ids]

    #     for id in ids:
    #         _id = self._to_uuid(id)
    #         anchor = self.__mem__.get(_id)
    #         if (
    #             not anchor
    #             and id not in self.__gc__
    #             and (_anchor := self._load_anchor_from_redis(_id))
    #         ):
    #             self.__mem__[id] = anchor = _anchor

    #         if anchor and (not filter or filter(anchor)):
    #             yield anchor

    #         else:
    #             yield from super().find(ids, filter)

    def find_by_id(self, id: UUID) -> Anchor | None:
        _id = self._to_uuid(id)
        data = self._load_anchor_from_redis(_id)
        return data

    def commit(self, anchor: Anchor | None = None, keys: Iterable[Anchor] = []) -> None:
        """Commit behaves like MongoDB but also syncs Redis."""

        if anchor:
            self.set(anchor)
            return
        if keys:
            for anc in keys:
                self.set(anc)

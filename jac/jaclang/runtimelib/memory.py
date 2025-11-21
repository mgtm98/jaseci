"""Core constructs for Jac Language."""

from __future__ import annotations

from dataclasses import dataclass, field
from pickle import dumps, loads
from shelve import Shelf, open
from typing import Any, Callable, Generator, Generic, Iterable, TypeVar, cast
from uuid import UUID

from pymongo import DeleteOne, MongoClient, UpdateOne

from .archetype import Anchor, NodeAnchor, Root, TANCH

import redis

ID = TypeVar("ID")


@dataclass
class Memory(Generic[ID, TANCH]):
    """Generic Memory Handler."""

    __mem__: dict[ID, TANCH] = field(default_factory=dict)
    __gc__: set[TANCH] = field(default_factory=set)

    def close(self) -> None:
        """Close memory handler."""
        self.__mem__.clear()
        self.__gc__.clear()

    def is_cached(self, id: ID) -> bool:
        """Check if id if already cached."""
        return id in self.__mem__

    def query(
        self, filter: Callable[[TANCH], bool] | None = None
    ) -> Generator[TANCH, None, None]:
        """Find anchors from memory with filter."""
        return (
            anchor for anchor in self.__mem__.values() if not filter or filter(anchor)
        )

    def all_root(self) -> Generator[Root, None, None]:
        """Get all the roots."""
        for anchor in self.query(lambda anchor: isinstance(anchor.archetype, Root)):
            yield cast(Root, anchor.archetype)

    def find(
        self,
        ids: ID | Iterable[ID],
        filter: Callable[[TANCH], TANCH] | None = None,
    ) -> Generator[TANCH, None, None]:
        """Find anchors from memory by ids with filter."""
        if not isinstance(ids, Iterable):
            ids = [ids]

        return (
            anchor
            for id in ids
            if (anchor := self.__mem__.get(id)) and (not filter or filter(anchor))
        )

    def find_one(
        self,
        ids: ID | Iterable[ID],
        filter: Callable[[TANCH], TANCH] | None = None,
    ) -> TANCH | None:
        """Find one anchor from memory by ids with filter."""
        return next(self.find(ids, filter), None)

    def find_by_id(self, id: ID) -> TANCH | None:
        """Find one by id."""
        return self.__mem__.get(id)

    def set(self, data: TANCH) -> None:
        """Save anchor to memory."""
        self.__mem__[data.id] = data

    def remove(self, ids: ID | Iterable[ID]) -> None:
        """Remove anchor/s from memory."""
        if not isinstance(ids, Iterable):
            ids = [ids]

        for id in ids:
            if anchor := self.__mem__.pop(id, None):
                self.__gc__.add(anchor)

    def commit(self, anchor: TANCH | None = None) -> None:
        """Commit all data from memory to datasource."""


@dataclass
class MongoDB(Memory[UUID, Anchor]):
    """MongoDB handler storing Python objects (pickled) with behavior exactly like ShelfStorage."""

    client: MongoClient | None = field(default=None)
    db_name: str = "jac_db"
    collection_name: str = "anchors"

    def __post_init__(self) -> None:
        if self.client is None:
            self.client = MongoClient(
                "mongodb+srv://juzailmlwork_db_user:e5OTI7p2DkaaGHnL@cluster0.e8eqk4i.mongodb.net/?appName=Cluster0/"
            )
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

    def _save_anchor(self, anchor: Anchor) -> None:
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

        print("uploaded anchor to item to mongodb ")

    def _delete_anchor(self, anchor: TANCH) -> None:
        _id = self._to_uuid(anchor.id)
        self.collection.delete_one({"_id": str(_id)})
        self.__mem__.pop(_id, None)
        self.__gc__.discard(anchor)

    # -------------------
    # FIND
    # -------------------
    def find(
        self,
        ids: UUID | Iterable[UUID],
        filter: Callable | None = None,
    ) -> Generator[Anchor, None, None]:
        if not isinstance(ids, Iterable) or isinstance(ids, (str, bytes)):
            ids = [ids]

        for id in ids:
            _id = self._to_uuid(id)

            # check memory first
            obj = self.__mem__.get(_id)
            if obj:
                if not filter or filter(obj):
                    yield obj
                continue

            # fetch from DB
            db_doc = self.collection.find_one({"_id": str(_id)})
            if db_doc:
                anchor = self._load_anchor(db_doc)
                if anchor is None:
                    continue
                self.__mem__[_id] = anchor
                yield anchor

    # -------------------
    # FIND ONE / BY ID
    # -------------------
    def find_one(
        self,
        ids: UUID | Iterable[UUID],
        filter: Callable[[TANCH], TANCH] | None = None,
    ) -> Anchor | None:
        return next(self.find(ids, filter), None)

    def find_by_id(self, id: UUID) -> Anchor | None:
        _id = self._to_uuid(id)
        obj = self.__mem__.get(_id)
        if obj:
            return obj

        db_obj = self.collection.find_one({"_id": str(_id)})
        if db_obj:
            anchor = self._load_anchor(db_obj)
            if anchor:
                self.__mem__[_id] = anchor
                return anchor
        return None

    def commit_bulk(self) -> None:
        """
        Faster bulk commit:
        - Deletes anchors in GC
        - Saves only updated anchors
        - Uses MongoDB bulk_write for speed
        """
        from jaclang.runtimelib.machine import JacMachineInterface as Jac
        from .archetype import NodeAnchor

        ops: list = []

        # ---------------------
        # Process deletions
        # ---------------------
        for anc in list(self.__gc__):
            _id = self._to_uuid(anc.id)
            ops.append(DeleteOne({"_id": str(_id)}))
            self.__mem__.pop(_id, None)
            self.__gc__.remove(anc)

        # ---------------------
        # Process updates
        # ---------------------
        print("number of keys in memory are", len(self.__mem__))
        for anc in list(self.__mem__.values()):
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

            # ---- Edge merging logic just like in _save_anchor ----
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

    def commit(self, anchor: TANCH | None = None) -> None:
        if anchor:
            print("MongoDB: committing single anchor")
            if anchor in self.__gc__:
                self._delete_anchor(anchor)
                self.__gc__.remove(anchor)
            else:
                self._save_anchor(anchor)
            return

        print("MongoDB: committing all anchors using bulk write")
        self.commit_bulk()

    def close(self) -> None:
        print("I am inside Mongodb closing")
        MongoDB.commit(self)
        super().close()


@dataclass
class RedisDB(Memory[UUID, Anchor]):
    """Redis-based Memory Handler inheriting MongoDB fallback."""

    redis_url: str = (
        "redis://:mypassword123@localhost:6379/0"  # "redis://localhost:6379/0"
    )
    redis_client: redis.Redis | None = field(default=None)

    def __post_init__(self) -> None:
        """Initialize Redis + MongoDB."""
        super().__init__()

        if self.redis_client is None:
            self.redis_client = redis.from_url(self.redis_url)

    def _redis_key(self, id: UUID) -> str:
        return f"anchor:{str(id)}"

    def _to_uuid(self, id: UUID | str) -> UUID:
        if not isinstance(id, UUID):
            return UUID(str(id))
        return id

    def _load_anchor_from_redis(self, id: UUID) -> Anchor | None:
        key = self._redis_key(id)
        raw = self.redis_client.get(key)
        if not raw:
            return None
        try:
            return loads(raw)
        except Exception:
            return None

    def _save_anchor(self, anchor: Anchor) -> None:
        """Save to MongoDB AND Redis."""
        self.redis_client.set(self._redis_key(anchor.id), dumps(anchor))

    def _delete_anchor(self, anchor: Anchor) -> None:
        """Delete from MongoDB AND Redis."""
        self.redis_client.delete(self._redis_key(anchor.id))

    def find(
        self,
        ids: UUID | Iterable[UUID],
        filter: Callable[[Anchor], bool] | None = None,
    ) -> Generator[Anchor, None, None]:

        if not isinstance(ids, Iterable):
            ids = [ids]

        for id in ids:
            _id = self._to_uuid(id)
            anchor = self.__mem__.get(_id)
            if (
                not anchor
                and id not in self.__gc__
                and (_anchor := self._load_anchor_from_redis(_id))
            ):
                self.__mem__[id] = anchor = _anchor

            if anchor and (not filter or filter(anchor)):
                yield anchor

            else:
                yield from super().find(ids, filter)

    def find_by_id(self, id: UUID) -> Anchor | None:
        _id = self._to_uuid(id)

        data = self.__mem__.get(_id)
        if not data:
            data = self._load_anchor_from_redis(_id)
            if data:
                self.__mem__[_id] = data
        return data

    def commit(self, anchor: Anchor | None = None) -> None:
        """Commit behaves like MongoDB but also syncs Redis."""

        if anchor:
            print("I am starting  redis commit for individual anchor")
            if anchor in self.__gc__:
                self._delete_anchor(anchor)
                self.__mem__.pop(anchor.id, None)
                # self.__gc__.remove(anchor)
            else:
                self._save_anchor(anchor)
            return
        print("I am starting  redis commit for all anchors")
        for anc in list(self.__gc__):
            self._delete_anchor(anc)

        for anc in list(self.__mem__.values()):
            self._save_anchor(anc)

        # Sync __mem__ → Redis after MongoDB commit
        for anc in list(self.__mem__.values()):
            try:
                self.redis_client.set(self._redis_key(anc.id), dumps(anc))
            except Exception:
                pass

    def close(self) -> None:
        """Close Redis + MongoDB memory."""
        print("I am closing redis memory")
        self.commit()
        super().close()


@dataclass
class ShelfStorage(Memory[UUID, Anchor]):
    """Shelf Handler."""

    __shelf__: Shelf[Anchor] | None = None

    def __init__(self, session: str | None = None) -> None:
        """Initialize memory handler."""
        super().__init__()
        self.__shelf__ = open(session) if session else None  # noqa: SIM115

    def commit(self, anchor: Anchor | None = None) -> None:
        """Commit all data from memory to datasource."""
        if isinstance(self.__shelf__, Shelf):
            if anchor:
                if anchor in self.__gc__:
                    self.__shelf__.pop(str(anchor.id), None)
                    self.__mem__.pop(anchor.id, None)
                    self.__gc__.remove(anchor)
                else:
                    self.sync_mem_to_db([anchor.id])
                return

            for anc in self.__gc__:
                self.__shelf__.pop(str(anc.id), None)
                self.__mem__.pop(anc.id, None)

            keys = set(self.__mem__.keys())

            # current memory
            self.sync_mem_to_db(keys)

            # additional after memory sync
            self.sync_mem_to_db(set(self.__mem__.keys() - keys))

    def close(self) -> None:
        """Close memory handler."""
        self.commit()

        if isinstance(self.__shelf__, Shelf):
            self.__shelf__.close()

        super().close()

    def sync_mem_to_db(self, keys: Iterable[UUID]) -> None:
        """Manually sync memory to db."""
        from jaclang.runtimelib.machine import JacMachineInterface as Jac

        if isinstance(self.__shelf__, Shelf):
            for key in keys:
                if (
                    (d := self.__mem__.get(key))
                    and d.persistent
                    and d.hash != hash(dumps(d))
                ):
                    _id = str(d.id)
                    if p_d := self.__shelf__.get(_id):
                        if (
                            isinstance(p_d, NodeAnchor)
                            and isinstance(d, NodeAnchor)
                            and p_d.edges != d.edges
                            and Jac.check_connect_access(d)
                        ):
                            if not d.edges and not isinstance(d.archetype, Root):
                                self.__shelf__.pop(_id, None)
                                continue
                            p_d.edges = d.edges

                        if Jac.check_write_access(d):
                            if hash(dumps(p_d.access)) != hash(dumps(d.access)):
                                p_d.access = d.access
                            if hash(dumps(p_d.archetype)) != hash(dumps(d.archetype)):
                                p_d.archetype = d.archetype

                        self.__shelf__[_id] = p_d
                    elif not (
                        isinstance(d, NodeAnchor)
                        and not isinstance(d.archetype, Root)
                        and not d.edges
                    ):
                        self.__shelf__[_id] = d

    def query(
        self, filter: Callable[[Anchor], bool] | None = None
    ) -> Generator[Any, None, None]:
        """Find anchors from memory with filter."""
        if isinstance(self.__shelf__, Shelf):
            for anchor in self.__shelf__.values():
                if not filter or filter(anchor):
                    if anchor.id not in self.__mem__:
                        self.__mem__[anchor.id] = anchor
                    yield anchor
        else:
            yield from super().query(filter)

    def find(
        self,
        ids: UUID | Iterable[UUID],
        filter: Callable[[Anchor], Anchor] | None = None,
    ) -> Generator[Anchor, None, None]:
        """Find anchors from datasource by ids with filter."""
        if not isinstance(ids, Iterable):
            ids = [ids]

        if isinstance(self.__shelf__, Shelf):
            for id in ids:
                anchor = self.__mem__.get(id)

                if (
                    not anchor
                    and id not in self.__gc__
                    and (_anchor := self.__shelf__.get(str(id)))
                ):
                    self.__mem__[id] = anchor = _anchor
                if anchor and (not filter or filter(anchor)):
                    yield anchor
        else:
            yield from super().find(ids, filter)

    def find_by_id(self, id: UUID) -> Anchor | None:
        """Find one by id."""
        data = super().find_by_id(id)

        if (
            not data
            and isinstance(self.__shelf__, Shelf)
            and (data := self.__shelf__.get(str(id)))
        ):
            self.__mem__[id] = data

        return data


@dataclass
class MultiHierarchyMemory:
    mem: Memory[UUID, Anchor]

    def __init__(self):
        redis = RedisDB()
        mongo = MongoDB()

    # ---- DOWNSTREAM (READS) ----
    def find(self, id: UUID) -> Anchor | None:
        # 1. Memory
        if obj := self.mem.get_local(id):
            return obj

        # 2. Redis
        if obj := self.redis.load_from_redis(id):
            self.mem.set_local(id, obj)
            return obj

        # 3. MongoDB
        if obj := self.mongo.load_from_mongo(id):
            self.redis.save_to_redis(obj)
            self.mem.set_local(id, obj)
            return obj

        return None

    # ---- UPSTREAM (WRITES) ----
    def commit(self, anchor: Anchor):
        # 1. Memory
        self.mem.set_local(anchor.id, anchor)

        # 2. Redis
        self.redis.save_to_redis(anchor)

        # 3. MongoDB
        self.mongo.save_to_mongo(anchor)

    # ---- DELETIONS ----
    def delete(self, id: UUID):
        # Remove from memory
        self.mem.mark_delete(id)

        # Remove from redis
        self.redis.redis_client.delete(f"anchor:{id}")

        # Remove from mongo
        self.mongo.client.db.anchors.delete_one({"_id": str(id)})
